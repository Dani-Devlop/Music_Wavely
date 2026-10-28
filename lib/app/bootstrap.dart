import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/app/providers.dart';
import 'package:wavely/app/wavely_app.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/features/telegram/telegram_bridge.dart';
import 'package:wavely/features/telegram/telegram_bridge_provider.dart';

/// DSN injected at compile time (`--dart-define=SENTRY_DSN=...`). Empty →
/// Sentry stays disabled (initializing with an empty DSN throws in
/// sentry 10, so `init` is skipped entirely).
const String _sentryDsn = String.fromEnvironment('SENTRY_DSN');

/// Sentry capture is a no-op unless a DSN was provided.
bool get _sentryEnabled => _sentryDsn.isNotEmpty;

/// Matches absolute-path-like substrings such as `/home/user/file.mp3` —
/// the same regex idea as `sanitizeForRelease` in core/utils/logger.dart.
final RegExp _pathLike = RegExp(r'(/[\w.\-]+){3,}');

/// Crash-only bootstrap: wires Sentry (when enabled), opens the database
/// (WAL mode) and runs the app inside a guarded zone.
///
/// Deliberately NOT initializing audio_service here — the mobile engine
/// initializes it lazily on first playback (see MobilePlaybackEngine).
Future<void> bootstrap() async {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _captureException(details.exception, details.stack ?? StackTrace.empty);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    _captureException(error, stackTrace);
    return true;
  };
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await _initSentry();
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase();
      await db.customSelect('PRAGMA journal_mode=WAL').get();
      runApp(
        ProviderScope(
          overrides: buildOverrides(db: db, prefs: prefs),
          child: const WavelyApp(),
        ),
      );
      // Stage 2.2: Telegram Mini App host lifecycle — web-only, no-op
      // elsewhere (the bridge stub). Never fatal: an unresponsive host
      // must not take the app down.
      if (kTelegramMode) {
        unawaited(_telegramHostReady());
      }
    },
    (error, stackTrace) => _captureException(error, stackTrace),
  );
}

/// Stage 2.2: signals the Telegram host that Wavely finished loading and
/// expands the Mini App. Failures are swallowed by the bridge contract.
Future<void> _telegramHostReady() async {
  try {
    final bridge = createTelegramBridge();
    if (bridge.snapshot().isInTelegram) {
      bridge
        ..ready()
        ..expand();
    }
  } on Object {
    // Bridge unavailable — the app still runs as a normal web build.
  }
}

Future<void> _initSentry() async {
  if (!_sentryEnabled) {
    return;
  }
  await SentryFlutter.init(
    (options) {
      options
        ..dsn = _sentryDsn
        ..sendDefaultPii = false
        ..tracesSampleRate = 0
        ..enableAutoSessionTracking = false
        ..beforeSend = _stripPii;
    },
  );
}

void _captureException(Object error, StackTrace stackTrace) {
  if (!_sentryEnabled) {
    return;
  }
  unawaited(Sentry.captureException(error, stackTrace: stackTrace));
}

/// Strips path-like breadcrumbs before an event leaves the device.
///
/// SentryEvent (sentry 10.2.0) exposes `breadcrumbs` as a getter/setter pair
/// and has no copyWith — the filter reassigns that field
/// (https://pub.dev/documentation/sentry/10.2.0/sentry/SentryEvent-class.html).
/// `sendDefaultPii = false` remains the primary PII defense; this is the
/// belt-and-braces pass over free-form breadcrumb messages.
SentryEvent _stripPii(SentryEvent event, Hint hint) {
  final breadcrumbs = event.breadcrumbs;
  if (breadcrumbs != null) {
    event.breadcrumbs = breadcrumbs
        .where(
          (breadcrumb) => !_pathLike.hasMatch(breadcrumb.message ?? ''),
        )
        .toList(growable: false);
  }
  // Stage 3 audit (SEC-17): exception messages and stack frames can embed
  // absolute paths too (Dio request URIs, file-system errors). sentry
  // 10.2.0 exposes `SentryException.value` / `SentryStackFrame.absPath` as
  // mutable fields and `frames` as an unmodifiable view over mutable frame
  // objects, so scrub in place.
  final exceptions = event.exceptions;
  if (exceptions != null) {
    for (final exception in exceptions) {
      exception.value = _scrubPaths(exception.value);
      final trace = exception.stackTrace;
      if (trace != null) {
        for (final frame in trace.frames) {
          final absPath = frame.absPath;
          if (absPath != null && _pathLike.hasMatch(absPath)) {
            frame.absPath = '[path]';
          }
        }
      }
    }
  }
  return event;
}

/// Replaces every path-like span in [text] with a `[path]` placeholder.
String? _scrubPaths(String? text) {
  if (text == null || !_pathLike.hasMatch(text)) {
    return text;
  }
  return text.replaceAllMapped(_pathLike, (_) => '[path]');
}

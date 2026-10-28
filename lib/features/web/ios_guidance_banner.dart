/// iOS PWA background-audio guidance banner (Stage 2.2).
///
/// Detects iPhone/iPad + standalone mode (via the conditional probe) and,
/// after the FIRST playback event, shows a dismissible [MaterialBanner]
/// pointing the user at the Telegram Mini App (where background audio
/// behaves better). Dismissal persists in SharedPreferences.
///
/// The whole flow is a no-op off-web and off-iOS — existing widget tests
/// never see it. Pure logic lives in [IosGuidanceGate] (unit-tested); the
/// banner itself is a thin ScaffoldMessenger call.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wavely/core/config/env.dart';
import 'package:wavely/core/utils/link_launcher.dart';
import 'package:wavely/core/utils/platform_utils.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/features/web/ios_probe_stub.dart'
    if (dart.library.js_interop) 'package:wavely/features/web/ios_probe_web.dart';
import 'package:wavely/playback/engines/engine_factory.dart';

/// Prefs key persisting the banner dismissal.
const String kIosBannerDismissedKey = 'web.iosBannerDismissed';

/// Pure gate logic (unit-testable): decides whether the banner may show.
class IosGuidanceGate {
  const IosGuidanceGate._();

  /// True when the banner is allowed to appear at all (web + iOS + not
  /// previously dismissed). [isWeb] is injected so tests on the VM can
  /// exercise both arms.
  static bool eligible({
    required bool isWeb,
    required bool isIos,
    required bool dismissed,
  }) =>
      isWeb && isIos && !dismissed;

  /// Deep link into the configured Telegram bot's Mini App.
  static Uri telegramMiniAppUrl() {
    final String? bot = WavelyEnv.telegramBotUsername;
    if (bot == null || bot.isEmpty) {
      return Uri.https('t.me', '/WavelyMusicBot', <String, String>{
        'startapp': 'wavely',
      });
    }
    return Uri.https('t.me', '/$bot', <String, String>{
      'startapp': 'wavely',
    });
  }
}

/// One-shot gate keyed on the first playback event.
StreamSubscription<Object?>? _firstPlaySubscription;

/// Shows the iOS guidance banner after the first playback event, when the
/// platform probe says iOS-PWA and the user has not dismissed it before.
/// Completely inert everywhere else (web+iOS only); never throws.
Future<void> maybeShowIosGuidanceBanner(
  BuildContext context,
  WidgetRef ref,
) async {
  try {
    if (!PlatformUtils.isWeb) {
      return;
    }
    const IosPlatformProbe probe = IosPlatformProbe();
    final bool dismissed = ref
            .read(sharedPrefsProvider)
            .getBool(kIosBannerDismissedKey) ??
        false;
    if (!IosGuidanceGate.eligible(
      isWeb: true,
      isIos: probe.isIos,
      dismissed: dismissed,
    )) {
      return;
    }
    if (_firstPlaySubscription != null) {
      return;
    }
    // Subscribe through the engine provider: the FIRST state event (the
    // user pressed play) triggers the banner. Failures disable the
    // feature — playback itself is never touched.
    final engine = ref.read(playbackEngineProvider);
    _firstPlaySubscription = engine.stateStream.cast<Object?>().listen((_) {
      unawaited(_showBanner(context, ref));
      unawaited(_cancelFirstPlaySubscription());
    });
  } on Object {
    // Guidance is best-effort; never fatal.
  }
}

Future<void> _cancelFirstPlaySubscription() async {
  await _firstPlaySubscription?.cancel();
  _firstPlaySubscription = null;
}

Future<void> _showBanner(BuildContext context, WidgetRef ref) async {
  if (!context.mounted) {
    return;
  }
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger.clearMaterialBanners();
  messenger.showMaterialBanner(
    MaterialBanner(
      key: const Key('ios-guidance-banner'),
      content: const Text(
        'Background audio on iPhone is limited. For a better experience, '
        'use the Wavely Telegram Mini App →',
      ),
      leading: const Icon(Icons.ios_share_rounded),
      actions: <Widget>[
        TextButton(
          key: const Key('ios-banner-open'),
          onPressed: () {
            final Uri url = IosGuidanceGate.telegramMiniAppUrl();
            unawaited(
              ref.read(linkLauncherProvider).launchExternal(url),
            );
          },
          child: const Text('Open Mini App'),
        ),
        TextButton(
          key: const Key('ios-banner-dismiss'),
          onPressed: () {
            unawaited(
              ref
                  .read(sharedPrefsProvider)
                  .setBool(kIosBannerDismissedKey, true),
            );
            messenger.clearMaterialBanners();
          },
          child: const Text('Dismiss'),
        ),
      ],
    ),
  );
}

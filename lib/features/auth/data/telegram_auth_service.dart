import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:wavely/core/config/env.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/core/utils/link_launcher.dart';
import 'package:wavely/features/auth/data/auth_api.dart';

/// Minimal secure-storage port so the Telegram flow can be tested without
/// platform channels ([FlutterSecureStorage] is a concrete platform class).
abstract interface class SecureTokenStore {
  /// Reads the value stored under [key], or null.
  Future<String?> read({required String key});

  /// Stores [value] under [key].
  Future<void> write({required String key, required String value});

  /// Removes the value stored under [key].
  Future<void> delete({required String key});
}

/// Production binding over flutter_secure_storage (keychain / keystore).
final class FlutterSecureTokenStore implements SecureTokenStore {
  /// Creates the binding.
  const FlutterSecureTokenStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// One-time pending sign-in record (token + creation time) parked in secure
/// storage while the user walks over to Telegram.
const String telegramPendingKey = 'wavely.telegram.pending';

/// Telegram passwordless sign-in (Stage 1.2, task B3).
///
/// Exact flow (reconciled with the `telegram-auth` edge function — see
/// docs/SUPABASE_SETUP.md for the full diagram):
///
///  1. A random v4 token is generated locally and parked in secure storage
///     under [telegramPendingKey] (JSON with `token` + `createdAt`).
///  2. `https://t.me/<bot>?start=<token>` is opened externally; the user
///     presses START.
///  3. The bot calls the `telegram-auth` edge function, which mints a
///     magic link for the mapped user and stores `{email, token_hash}`
///     beside the token (5-minute TTL).
///  4. This service polls `rpc('redeem_telegram_session', {token})` every
///     [pollInterval] — the security-definer SQL function atomically marks
///     the row used and returns `{email, token_hash}` (the flow's original
///     "return a JWT" idea is impossible: Supabase has no admin API that
///     mints session JWTs, so the client finishes sign-in itself).
///  5. `verifyMagicLink` (`auth.verifyOTP`, type magiclink) establishes the
///     session client-side — no `setSession` needed, verify does it.
///  6. Cleanup: secure-storage entry deleted, poll timer stopped.
///
/// Transient errors (rpc/network hiccups, bot not pressed yet) keep polling
/// until [timeout], then surface 'Timed out — start the bot chat again'.
/// All collaborators are injectable for tests.
class TelegramAuthService {
  /// Creates the service.
  ///
  /// [api] — Supabase port; [storage] — secure token store; [launch] —
  /// external URL opener; [pollInterval] / [timeout] — polling cadence and
  /// total budget; [botUsername] — overrides `WavelyEnv.telegramBotUsername`
  /// (tests must inject, dart-defines cannot be set in test runs);
  /// [now] — injectable clock for the deadline; [uuid] — token generator.
  TelegramAuthService(
    AuthApi api, {
    SecureTokenStore? storage,
    Future<bool> Function(Uri url)? launch,
    this.pollInterval = const Duration(seconds: 2),
    this.timeout = const Duration(minutes: 5),
    String? botUsername,
    DateTime Function()? now,
    Uuid? uuid,
  })  : _api = api,
        _storage = storage ?? const FlutterSecureTokenStore(),
        _launch = launch ?? _defaultLaunch,
        _botUsername = botUsername,
        _now = now ?? DateTime.now,
        _uuid = uuid ?? const Uuid();

  final AuthApi _api;
  final SecureTokenStore _storage;
  final Future<bool> Function(Uri url) _launch;
  final String? _botUsername;
  final DateTime Function() _now;
  final Uuid _uuid;

  /// How often the redeem rpc is polled (2 s in production).
  final Duration pollInterval;

  /// Total polling budget (5 min in production).
  final Duration timeout;

  _PendingPoll? _pending;

  static Future<bool> _defaultLaunch(Uri url) =>
      const UrlLinkLauncher().launchExternal(url);

  /// Runs the whole flow and completes when the session is established, the
  /// budget is exhausted, or [stop] cancels the run.
  Future<Result<Session?>> start() async {
    if (_pending != null) {
      return Result<Session?>.err(
        Failure.unknown(message: 'A Telegram sign-in is already running.'),
      );
    }
    final bot = _botUsername ?? WavelyEnv.telegramBotUsername;
    if (bot == null || bot.trim().isEmpty) {
      return Result<Session?>.err(
        Failure.unknown(
          message: 'TELEGRAM_BOT_USERNAME is not configured.',
        ),
      );
    }

    final token = _uuid.v4();
    try {
      await _storage.write(
        key: telegramPendingKey,
        value: jsonEncode(<String, String>{
          'token': token,
          'createdAt': _now().toIso8601String(),
        }),
      );
    } catch (error) {
      return Result<Session?>.err(
        Failure.storage(
          message: 'Could not stage the Telegram sign-in.',
          cause: error,
        ),
      );
    }

    final url = Uri.https('t.me', '/$bot', <String, String>{
      'start': token,
    });
    var opened = false;
    try {
      opened = await _launch(url);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      await _deletePending();
      return Result<Session?>.err(
        Failure.unknown(message: 'Could not open Telegram.'),
      );
    }

    final completer = Completer<Result<Session?>>();
    final deadline = _now().add(timeout);
    var pollInFlight = false;
    final timer = Timer.periodic(pollInterval, (_) async {
      if (pollInFlight || completer.isCompleted) return;
      pollInFlight = true;
      try {
        if (_now().isAfter(deadline)) {
          _complete(
            completer,
            Result<Session?>.err(
              Failure.unknown(
                message: 'Timed out — start the bot chat again',
              ),
            ),
          );
          return;
        }
        final row = await _redeemOnce(token);
        if (row == null) return; // not redeemed yet — keep polling
        final (email, tokenHash) = row;
        final session =
            await _api.verifyMagicLink(email: email, tokenHash: tokenHash);
        if (session == null) {
          _complete(
            completer,
            Result<Session?>.err(
              Failure.unknown(
                message: 'Telegram sign-in failed — try again.',
              ),
            ),
          );
          return;
        }
        _complete(completer, Result<Session?>.success(session));
      } catch (_) {
        // Transient rpc/network error — keep polling until the deadline.
      } finally {
        pollInFlight = false;
      }
    });
    _pending = _PendingPoll(timer, completer);
    return completer.future;
  }

  /// Cancels any in-flight poll loop (screen dispose / user backs out).
  /// A pending [start] future completes with a 'cancelled' failure.
  void stop() {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    pending.timer.cancel();
    unawaited(_deletePending());
    if (!pending.completer.isCompleted) {
      pending.completer.complete(
        Result<Session?>.err(
          Failure.unknown(message: 'Telegram sign-in cancelled.'),
        ),
      );
    }
  }

  /// Returns `(email, tokenHash)` once redeemed, or null while pending.
  Future<(String, String)?> _redeemOnce(String token) async {
    final rows = await _api.rpc(
      'redeem_telegram_session',
      params: <String, dynamic>{'token': token},
    );
    for (final row in rows) {
      final email = row['email'] as String?;
      final tokenHash = row['token_hash'] as String?;
      if (email != null &&
          email.isNotEmpty &&
          tokenHash != null &&
          tokenHash.isNotEmpty) {
        return (email, tokenHash);
      }
    }
    return null;
  }

  void _complete(
    Completer<Result<Session?>> completer,
    Result<Session?> result,
  ) {
    if (completer.isCompleted) return;
    // Stage 3 audit (BUG-12): cancel the poll timer with the pending flow —
    // it previously kept firing a no-op 2 s timer for the rest of the
    // session and allowed overlapping start() calls.
    final _PendingPoll? pending = _pending;
    _pending = null;
    pending?.timer.cancel();
    unawaited(_deletePending());
    completer.complete(result);
  }

  Future<void> _deletePending() async {
    try {
      await _storage.delete(key: telegramPendingKey);
    } catch (_) {
      // Best-effort cleanup; the entry is overwritten on the next attempt.
    }
  }
}

final class _PendingPoll {
  const _PendingPoll(this.timer, this.completer);

  final Timer timer;
  final Completer<Result<Session?>> completer;
}

/// Feature-scoped binding (Stage 1.2 conventions: providers live inside the
/// feature; the telegram screen overrides this with a fast fake in tests).
final telegramAuthServiceProvider = Provider<TelegramAuthService>(
  (ref) => TelegramAuthService(ref.watch(supabaseAuthApiProvider)),
);

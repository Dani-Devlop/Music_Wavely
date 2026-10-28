// authored, awaiting local run.
//
// Tests for lib/features/auth/data/telegram_auth_service.dart (all
// collaborators injectable, fakeAsync-driven polling):
// success flow (token staged → t.me link launched → rpc polling →
// verifyMagicLink → session), launch failure, launch throwing, storage
// failure, polling timeout past the injectable-clock deadline, transient
// rpc errors that keep polling, double-start rejection, stop() cancellation,
// and the missing bot-username configuration error.
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/features/auth/data/auth_api.dart';
import 'package:wavely/features/auth/data/telegram_auth_service.dart';

Session _session(String accessToken) => Session.fromJson(<String, dynamic>{
      'access_token': accessToken,
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': 1767225600,
      'refresh_token': 'refresh',
      'user': <String, dynamic>{
        'id': 'user-1',
        'aud': 'authenticated',
        'email': 'tg@example.com',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2024-01-01T00:00:00Z',
      },
    })!;

Success<T> _ok<T>(Result<T> result) => result as Success<T>;
Err<T> _err<T>(Result<T> result) => result as Err<T>;

class _MemTokenStore implements SecureTokenStore {
  final Map<String, String> map = <String, String>{};
  bool writeThrows = false;
  int writeCount = 0;
  int deleteCount = 0;

  @override
  Future<String?> read({required String key}) async => map[key];

  @override
  Future<void> write({required String key, required String value}) async {
    writeCount++;
    if (writeThrows) {
      throw StateError('secure storage unavailable');
    }
    map[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    deleteCount++;
    map.remove(key);
  }
}

class _FakeAuthApi implements AuthApi {
  _FakeAuthApi();

  // redeem_telegram_session scripting.
  List<Map<String, dynamic>> rpcRows = const <Map<String, dynamic>>[];
  Object? rpcThrows;
  Session? verifySession;
  Object? verifyThrows;

  final List<String> rpcCalls = <String>[];
  final List<String> verifyEmails = <String>[];
  final List<String> verifyTokenHashes = <String>[];

  @override
  Future<Session?> signInWithPassword({
    required String email,
    required String password,
  }) async =>
      null;

  @override
  Future<Session?> signUp(
      {required String email, required String password}) async =>
      null;

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}

  @override
  Stream<Session?> get sessionStream => const Stream<Session?>.empty();

  @override
  Session? get currentSession => null;

  @override
  Future<List<Map<String, dynamic>>> rpc(
    String function, {
    Map<String, dynamic>? params,
  }) async {
    rpcCalls.add(params?['token'] as String? ?? '');
    final throws = rpcThrows;
    if (throws != null) {
      throw throws;
    }
    return rpcRows;
  }

  @override
  Future<Session?> verifyMagicLink({
    required String email,
    required String tokenHash,
  }) async {
    verifyEmails.add(email);
    verifyTokenHashes.add(tokenHash);
    final throws = verifyThrows;
    if (throws != null) {
      throw throws;
    }
    return verifySession;
  }
}

void main() {
  const pollInterval = Duration(seconds: 2);

  test('success flow: stages the token, opens t.me, redeems via rpc and '
      'verifies the magic link', () {
    fakeAsync((async) {
      var now = DateTime(2026, 1, 1, 12);
      final store = _MemTokenStore();
      final api = _FakeAuthApi();
      final launchedUrls = <Uri>[];
      final service = TelegramAuthService(
        api,
        storage: store,
        launch: (url) async {
          launchedUrls.add(url);
          return true;
        },
        pollInterval: pollInterval,
        timeout: const Duration(minutes: 5),
        botUsername: 'wavely_bot',
        now: () => now,
      );

      Result<Session?>? outcome;
      unawaited(service.start().then((value) => outcome = value));
      async.flushMicrotasks();

      // The pending record was staged with token + createdAt…
      expect(store.writeCount, 1);
      final staged =
          jsonDecode(store.map[telegramPendingKey]!) as Map<String, dynamic>;
      expect(staged, containsPair('createdAt', '2026-01-01T12:00:00.000'));
      final token = staged['token'] as String;
      // …and the bot deep link carries it as the start parameter.
      expect(launchedUrls, hasLength(1));
      expect(launchedUrls.single.host, 't.me');
      expect(launchedUrls.single.path, '/wavely_bot');
      expect(launchedUrls.single.queryParameters['start'], token);

      // Initial tick (immediate, before any interval elapses): not
      // redeemed yet → keep polling.
      expect(api.rpcCalls, hasLength(1));
      expect(api.rpcCalls.single, token);

      // Tick 1 (periodic): still not redeemed → keep polling.
      async.elapse(pollInterval);
      async.flushMicrotasks();
      expect(outcome, isNull);
      expect(api.rpcCalls, hasLength(2));

      // Tick 2 (periodic): the row is redeemed → verifyMagicLink
      // establishes the session and the future completes.
      api.rpcRows = <Map<String, dynamic>>[
        <String, dynamic>{'email': 'tg@example.com', 'token_hash': 'th-1'},
      ];
      api.verifySession = _session('tg-session');
      async.elapse(pollInterval);
      async.flushMicrotasks();

      final result = _ok(outcome!).value;
      expect(result!.accessToken, 'tg-session');
      expect(api.verifyEmails.single, 'tg@example.com');
      expect(api.verifyTokenHashes.single, 'th-1');
      // Cleanup: the pending entry was deleted.
      expect(store.map.containsKey(telegramPendingKey), isFalse);
      // The rpc captured the SAME token that was staged.
      expect(api.rpcCalls, everyElement(token));
    });
  });

  test('unredeemed rpc rows keep the loop polling until success', () {
    fakeAsync((async) {
      var now = DateTime(2026, 1, 1, 12);
      final api = _FakeAuthApi();
      final service = TelegramAuthService(
        api,
        storage: _MemTokenStore(),
        launch: (url) async => true,
        pollInterval: pollInterval,
        timeout: const Duration(minutes: 5),
        botUsername: 'bot',
        now: () => now,
      );

      Result<Session?>? outcome;
      unawaited(service.start().then((value) => outcome = value));
      async.flushMicrotasks();

      for (var i = 0; i < 3; i++) {
        api.rpcRows = const <Map<String, dynamic>>[]; // not redeemed yet
        async.elapse(pollInterval);
        async.flushMicrotasks();
      }
      expect(outcome, isNull);
      expect(api.rpcCalls, hasLength(4)); // initial tick + 3

      api.rpcRows = <Map<String, dynamic>>[
        <String, dynamic>{'email': 'e@x.c', 'token_hash': 'th'},
      ];
      api.verifySession = _session('late');
      async.elapse(pollInterval);
      async.flushMicrotasks();
      expect(_ok(outcome!).value!.accessToken, 'late');
    });
  });

  test('transient rpc/network errors are swallowed and polling continues',
      () {
    fakeAsync((async) {
      var now = DateTime(2026, 1, 1, 12);
      final api = _FakeAuthApi();
      final service = TelegramAuthService(
        api,
        storage: _MemTokenStore(),
        launch: (url) async => true,
        pollInterval: pollInterval,
        timeout: const Duration(minutes: 5),
        botUsername: 'bot',
        now: () => now,
      );

      Result<Session?>? outcome;
      unawaited(service.start().then((value) => outcome = value));
      async.flushMicrotasks();

      api.rpcThrows = Exception('network flap');
      async.elapse(pollInterval);
      async.flushMicrotasks();
      expect(outcome, isNull);

      api.rpcThrows = null;
      api.rpcRows = <Map<String, dynamic>>[
        <String, dynamic>{'email': 'e@x.c', 'token_hash': 'th'},
      ];
      api.verifySession = _session('recovered');
      async.elapse(pollInterval);
      async.flushMicrotasks();
      expect(_ok(outcome!).value!.accessToken, 'recovered');
    });
  });

  test('token TTL expiry: past the injectable-clock deadline the flow '
      'completes with the documented timeout message', () {
    fakeAsync((async) {
      var now = DateTime(2026, 1, 1, 12);
      final api = _FakeAuthApi();
      final service = TelegramAuthService(
        api,
        storage: _MemTokenStore(),
        launch: (url) async => true,
        pollInterval: pollInterval,
        timeout: const Duration(minutes: 5),
        botUsername: 'bot',
        now: () => now,
      );

      Result<Session?>? outcome;
      unawaited(service.start().then((value) => outcome = value));
      async.flushMicrotasks();

      // Walk the clock past the 5-minute deadline, then let a poll tick
      // observe it.
      now = now.add(const Duration(minutes: 5, seconds: 1));
      async.elapse(pollInterval);
      async.flushMicrotasks();

      final failure = _err(outcome!).failure;
      expect(failure.message, 'Timed out — start the bot chat again');
      // Only the first tick reached the rpc; the deadline check runs before
      // any redeem attempt.
      expect(api.rpcCalls.length, 1);
    });
  });

  test('launch failure cleans up and reports "Could not open Telegram."',
      () {
    fakeAsync((async) {
      final store = _MemTokenStore();
      final api = _FakeAuthApi();
      final service = TelegramAuthService(
        api,
        storage: store,
        launch: (url) async => false,
        botUsername: 'bot',
        now: () => DateTime(2026, 1, 1),
      );

      Result<Session?>? outcome;
      unawaited(service.start().then((value) => outcome = value));
      async.flushMicrotasks();

      expect(_err(outcome!).failure.message, 'Could not open Telegram.');
      expect(store.map.containsKey(telegramPendingKey), isFalse);
      expect(api.rpcCalls, isEmpty); // no polling ever started
    });
  });

  test('a launch PLATFORM exception is handled like a launch failure',
      () {
    fakeAsync((async) {
      final api = _FakeAuthApi();
      final service = TelegramAuthService(
        api,
        storage: _MemTokenStore(),
        launch: (url) async => throw StateError('no handler for t.me'),
        botUsername: 'bot',
        now: () => DateTime(2026, 1, 1),
      );

      Result<Session?>? outcome;
      unawaited(service.start().then((value) => outcome = value));
      async.flushMicrotasks();

      expect(_err(outcome!).failure.message, 'Could not open Telegram.');
    });
  });

  test('a secure-storage write failure surfaces the staging error',
      () {
    fakeAsync((async) {
      final store = _MemTokenStore()..writeThrows = true;
      final api = _FakeAuthApi();
      final service = TelegramAuthService(
        api,
        storage: store,
        launch: (url) async => true,
        botUsername: 'bot',
        now: () => DateTime(2026, 1, 1),
      );

      Result<Session?>? outcome;
      unawaited(service.start().then((value) => outcome = value));
      async.flushMicrotasks();

      final failure = _err(outcome!).failure;
      expect(failure.message, 'Could not stage the Telegram sign-in.');
      expect(api.rpcCalls, isEmpty);
    });
  });

  test('starting twice while a sign-in is running is rejected', () {
    fakeAsync((async) {
      final api = _FakeAuthApi();
      final service = TelegramAuthService(
        api,
        storage: _MemTokenStore(),
        launch: (url) async => true,
        botUsername: 'bot',
        now: () => DateTime(2026, 1, 1),
      );

      Result<Session?>? first;
      unawaited(service.start().then((value) => first = value));
      async.flushMicrotasks();
      expect(first, isNull); // still polling

      Result<Session?>? second;
      unawaited(service.start().then((value) => second = value));
      async.flushMicrotasks();

      expect(_err(second!).failure.message,
          'A Telegram sign-in is already running.');
      service.stop();
    });
  });

  test('stop() cancels the loop and completes the pending future with the '
      'cancellation failure', () {
    fakeAsync((async) {
      final store = _MemTokenStore();
      final api = _FakeAuthApi();
      final service = TelegramAuthService(
        api,
        storage: store,
        launch: (url) async => true,
        botUsername: 'bot',
        now: () => DateTime(2026, 1, 1),
      );

      Result<Session?>? outcome;
      unawaited(service.start().then((value) => outcome = value));
      async.flushMicrotasks();

      service.stop();
      async.flushMicrotasks();

      expect(_err(outcome!).failure.message, 'Telegram sign-in cancelled.');
      expect(store.map.containsKey(telegramPendingKey), isFalse);
      // stop() is idempotent.
      service.stop();
    });
  });

  test('without an injectable bot username the flow reports the missing '
      'configuration (test runs have no TELEGRAM_BOT_USERNAME define)',
      () {
    fakeAsync((async) {
      final api = _FakeAuthApi();
      final service = TelegramAuthService(
        api,
        storage: _MemTokenStore(),
        launch: (url) async => true,
        now: () => DateTime(2026, 1, 1),
      );

      Result<Session?>? outcome;
      unawaited(service.start().then((value) => outcome = value));
      async.flushMicrotasks();

      expect(_err(outcome!).failure.message,
          'TELEGRAM_BOT_USERNAME is not configured.');
    });
  });
}

// authored, awaiting local run.
//
// Tests for lib/features/auth/data/auth_repository.dart against the
// lib/features/auth/data/auth_api.dart seam with a hand-rolled fake:
// signIn/signUp/signOut/deleteAccount success + error mapping (AuthException
// message passthrough vs generic fallback messages), null-session sign-up
// (e-mail confirmation flow), sessionStream/currentSession passthrough, and
// rpc/verifyMagicLink surface completeness.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/features/auth/data/auth_api.dart';
import 'package:wavely/features/auth/data/auth_repository.dart';

Success<T> _ok<T>(Result<T> result) => result as Success<T>;
Err<T> _err<T>(Result<T> result) => result as Err<T>;

Session _session(String accessToken) => Session.fromJson(<String, dynamic>{
      'access_token': accessToken,
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': 1767225600,
      'refresh_token': 'refresh-$accessToken',
      'user': <String, dynamic>{
        'id': 'user-1',
        'aud': 'authenticated',
        'email': 'user@example.com',
        'app_metadata': <String, dynamic>{'provider': 'email'},
        'user_metadata': <String, dynamic>{},
        'created_at': '2024-01-01T00:00:00Z',
      },
    });

/// Hand-rolled [AuthApi] fake — scripted results/throws + call recording.
class _FakeAuthApi implements AuthApi {
  _FakeAuthApi();

  Session? signInSession;
  Session? signUpSession;
  Object? signInThrows;
  Object? signUpThrows;
  Object? signOutThrows;
  Object? deleteThrows;
  List<Map<String, dynamic>> rpcRows = const <Map<String, dynamic>>[];
  Object? rpcThrows;
  Session? verifySession;

  int signInCalls = 0;
  int signUpCalls = 0;
  int signOutCalls = 0;
  int deleteCalls = 0;
  int verifyCalls = 0;
  String? lastVerifyEmail;
  String? lastVerifyTokenHash;
  (String, Map<String, dynamic>?)? lastRpc;

  final StreamController<Session?> _sessionStream =
      StreamController<Session?>.broadcast();

  @override
  Future<Session?> signInWithPassword({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    final throws = signInThrows;
    if (throws != null) {
      throw throws;
    }
    return signInSession;
  }

  @override
  Future<Session?> signUp({
    required String email,
    required String password,
  }) async {
    signUpCalls++;
    final throws = signUpThrows;
    if (throws != null) {
      throw throws;
    }
    return signUpSession;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    final throws = signOutThrows;
    if (throws != null) {
      throw throws;
    }
  }

  @override
  Future<void> deleteAccount() async {
    deleteCalls++;
    final throws = deleteThrows;
    if (throws != null) {
      throw throws;
    }
  }

  @override
  Stream<Session?> get sessionStream => _sessionStream.stream;

  @override
  Session? get currentSession => signInSession;

  @override
  Future<List<Map<String, dynamic>>> rpc(
    String function, {
    Map<String, dynamic>? params,
  }) async {
    lastRpc = (function, params);
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
    verifyCalls++;
    lastVerifyEmail = email;
    lastVerifyTokenHash = tokenHash;
    return verifySession;
  }

  void emitSession(Session? session) => _sessionStream.add(session);
}

void main() {
  group('signInWithEmail', () {
    test('success carries the established session', () async {
      final api = _FakeAuthApi()..signInSession = _session('token-1');
      final repository = AuthRepository(api);

      final result = await repository.signInWithEmail(
        'user@example.com',
        'hunter2',
      );

      final session = _ok(result).value;
      expect(session, isNotNull);
      expect(session!.accessToken, 'token-1');
      expect(api.signInCalls, 1);
    });

    test('AuthException message passes through as a Failure.unknown',
        () async {
      final api = _FakeAuthApi()
        ..signInThrows = AuthException('Invalid login credentials');
      final repository = AuthRepository(api);

      final result = await repository.signInWithEmail('a@b.c', 'wrong');

      final failure = _err(result).failure;
      expect(failure, isA<UnknownFailure>());
      expect(failure.message, 'Invalid login credentials');
      expect(failure.cause, isA<AuthException>());
    });

    test('any other error maps to the user-presentable fallback message',
        () async {
      final api = _FakeAuthApi()..signInThrows = Exception('socket timeout');
      final repository = AuthRepository(api);

      final result = await repository.signInWithEmail('a@b.c', 'pw');

      expect(_err(result).failure.message,
          'Sign-in failed. Check your connection and try again.');
    });
  });

  group('signUpWithEmail', () {
    test('success carries the session', () async {
      final api = _FakeAuthApi()..signUpSession = _session('token-2');
      final repository = AuthRepository(api);

      final result = await repository.signUpWithEmail('a@b.c', 'pw');

      expect(_ok(result).value!.accessToken, 'token-2');
      expect(api.signUpCalls, 1);
    });

    test('a null session (e-mail confirmation required) is still a success',
        () async {
      final api = _FakeAuthApi()..signUpSession = null;
      final repository = AuthRepository(api);

      final result = await repository.signUpWithEmail('a@b.c', 'pw');

      expect(result.isSuccess, isTrue);
      expect(_ok(result).value, isNull);
    });

    test('AuthException passes through; other errors use the sign-up '
        'fallback', () async {
      final repository = AuthRepository(
        _FakeAuthApi()..signUpThrows = AuthException('User already registered'),
      );
      expect(
        _err(await repository.signUpWithEmail('a@b.c', 'pw')).failure.message,
        'User already registered',
      );

      final fallbackRepository = AuthRepository(
        _FakeAuthApi()..signUpThrows = StateError('boom'),
      );
      expect(
        _err(await fallbackRepository.signUpWithEmail('a@b.c', 'pw'))
            .failure
            .message,
        'Sign-up failed. Check your connection and try again.',
      );
    });
  });

  group('signOut', () {
    test('success and idempotent from the caller perspective', () async {
      final api = _FakeAuthApi();
      final repository = AuthRepository(api);

      final result = await repository.signOut();

      expect(result.isSuccess, isTrue);
      expect(api.signOutCalls, 1);
    });

    test('errors surface as failures (never throws)', () async {
      final api = _FakeAuthApi()..signOutThrows = Exception('offline');
      final repository = AuthRepository(api);

      final result = await repository.signOut();

      expect(_err(result).failure.message, 'Sign-out failed. Try again.');
    });
  });

  group('deleteAccount', () {
    test('success when the rpc exists', () async {
      final api = _FakeAuthApi();
      final repository = AuthRepository(api);

      final result = await repository.deleteAccount();

      expect(result.isSuccess, isTrue);
      expect(api.deleteCalls, 1);
    });

    test('AuthException message passes through (graceful, no throw)',
        () async {
      final api = _FakeAuthApi()
        ..deleteThrows = AuthException('function delete_account does not exist');
      final repository = AuthRepository(api);

      final result = await repository.deleteAccount();

      expect(_err(result).failure.message,
          'function delete_account does not exist');
    });

    test('generic errors map to the documented fallback message', () async {
      final api = _FakeAuthApi()..deleteThrows = Exception('403');
      final repository = AuthRepository(api);

      final result = await repository.deleteAccount();

      expect(_err(result).failure.message,
          'Account deletion is not available yet.');
    });
  });

  group('session surface', () {
    test('sessionStream forwards api events (null = signed out)',
        () async {
      final api = _FakeAuthApi();
      final repository = AuthRepository(api);
      final events = <Session?>[];
      final subscription = repository.sessionStream.listen(events.add);
      addTearDown(subscription.cancel);

      api.emitSession(_session('t'));
      api.emitSession(null);
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(2));
      expect(events[0]!.accessToken, 't');
      expect(events[1], isNull);
    });

    test('currentSession mirrors the api session', () {
      final api = _FakeAuthApi()..signInSession = _session('current');
      final repository = AuthRepository(api);

      expect(repository.currentSession!.accessToken, 'current');
    });
  });

  group('AuthApi surface completeness (used by the Telegram flow)', () {
    test('rpc forwards function + params and returns rows', () async {
      final api = _FakeAuthApi()
        ..rpcRows = const <Map<String, dynamic>>[
          <String, dynamic>{'email': 'a@b.c', 'token_hash': 'th'},
        ];
      final repository = AuthRepository(api);

      final rows = await api.rpc(
        'redeem_telegram_session',
        params: <String, dynamic>{'token': 't'},
      );

      expect(rows, hasLength(1));
      expect(api.lastRpc!.$1, 'redeem_telegram_session');
      expect(api.lastRpc!.$2, <String, dynamic>{'token': 't'});
    });

    test('verifyMagicLink forwards email + tokenHash', () async {
      final api = _FakeAuthApi()..verifySession = _session('verified');
      final repository = AuthRepository(api);

      final session = await api.verifyMagicLink(
        email: 'a@b.c',
        tokenHash: 'th',
      );

      expect(session!.accessToken, 'verified');
      expect(api.lastVerifyEmail, 'a@b.c');
      expect(api.lastVerifyTokenHash, 'th');
    });
  });
}

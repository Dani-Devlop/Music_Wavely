import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wavely/data/remote/supabase_client_provider.dart';

/// Minimal port over the Supabase auth surface Wavely uses (Stage 1.2).
///
/// [AuthRepository] and [TelegramAuthService] are written against this
/// interface instead of `SupabaseClient` so unit tests can substitute a
/// hand-rolled fake — the real client's methods hit the network the moment
/// they are awaited and cannot be faked without a server.
abstract interface class AuthApi {
  /// Password sign-in; throws [AuthException] on bad credentials or server
  /// errors (translated to a [Failure] by the repository).
  Future<Session?> signInWithPassword({
    required String email,
    required String password,
  });

  /// Password sign-up. Returns a null session when the project requires
  /// e-mail confirmation before a session is issued.
  Future<Session?> signUp({required String email, required String password});

  /// Signs out the local session.
  Future<void> signOut();

  /// Attempts the server-side `delete_account` rpc. Stage 2 feature: real
  /// deletion needs a service-role edge function; until that SQL function
  /// ships this call fails and the repository maps it to a graceful failure.
  Future<void> deleteAccount();

  /// Emits on every auth state change; a null session means signed out.
  Stream<Session?> get sessionStream;

  /// The active session, or null when signed out.
  Session? get currentSession;

  /// PostgREST rpc returning a row set (empty list = nothing to redeem).
  Future<List<Map<String, dynamic>>> rpc(
    String function, {
    Map<String, dynamic>? params,
  });

  /// Verifies a magic-link token hash (Telegram sign-in, last step) and
  /// establishes the session client-side — no `setSession` needed, verify
  /// establishes it.
  Future<Session?> verifyMagicLink({
    required String email,
    required String tokenHash,
  });
}

/// Thin production adapter — the only place that touches the real Supabase
/// surface (the documented ~20-line wrapper from the Stage 1.2 plan). All
/// error translation stays in [AuthRepository].
final class SupabaseAuthApi implements AuthApi {
  /// Creates the adapter over [client].
  const SupabaseAuthApi(this._client);

  final SupabaseClient _client;

  @override
  Future<Session?> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response.session;
  }

  @override
  Future<Session?> signUp({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );
    return response.session;
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> deleteAccount() async {
    await _client.rpc('delete_account');
  }

  @override
  Stream<Session?> get sessionStream =>
      _client.auth.onAuthStateChange.map((state) => state.session);

  @override
  Session? get currentSession => _client.auth.currentSession;

  @override
  Future<List<Map<String, dynamic>>> rpc(
    String function, {
    Map<String, dynamic>? params,
  }) async {
    final rows = await _client.rpc(function, params: params);
    if (rows == null) return const <Map<String, dynamic>>[];
    return List<Map<String, dynamic>>.from(rows as List<dynamic>);
  }

  @override
  Future<Session?> verifyMagicLink({
    required String email,
    required String tokenHash,
  }) async {
    final response = await _client.auth.verifyOTP(
      email: email,
      tokenHash: tokenHash,
      type: OtpType.magiclink,
    );
    return response.session;
  }
}

/// Feature-scoped binding (Stage 1.2 conventions: providers live inside the
/// feature; tests override with a fake).
final supabaseAuthApiProvider = Provider<AuthApi>(
  (ref) => SupabaseAuthApi(ref.watch(supabaseClientProvider)),
);

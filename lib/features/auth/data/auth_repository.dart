import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/features/auth/data/auth_api.dart';

/// Repository around Supabase auth (Stage 1.2, task B3).
///
/// Every call is wrapped and returns [Result] — the repository never throws.
/// The Supabase surface is reached through [AuthApi] so unit tests use a
/// hand-rolled fake ([SupabaseAuthApi] is the production adapter).
class AuthRepository {
  /// Creates the repository over [api].
  const AuthRepository(this._api);

  final AuthApi _api;

  /// Signs in with e-mail + password. The [Result] carries the established
  /// session, or a user-presentable [Failure] (e.g. 'Invalid login
  /// credentials' passed through from Supabase).
  Future<Result<Session?>> signInWithEmail(String email, String password) =>
      _guard(
        () => _api.signInWithPassword(email: email, password: password),
        fallbackMessage:
            'Sign-in failed. Check your connection and try again.',
      );

  /// Signs up with e-mail + password.
  ///
  /// NOTE on e-mail confirmation: when the project has
  /// `[auth.email] enable_confirmations = true` (recommended in production),
  /// Supabase sends a confirmation mail and returns a NULL session — callers
  /// must surface 'Check your inbox' instead of 'signed in' whenever the
  /// success session is null. Local dev keeps confirmations off.
  Future<Result<Session?>> signUpWithEmail(String email, String password) =>
      _guard(
        () => _api.signUp(email: email, password: password),
        fallbackMessage:
            'Sign-up failed. Check your connection and try again.',
      );

  /// Signs out. Idempotent from the caller's point of view (errors still
  /// surface as a [Failure] — never a throw).
  Future<Result<void>> signOut() => _guard(
        _api.signOut,
        fallbackMessage: 'Sign-out failed. Try again.',
      );

  /// Account deletion.
  ///
  /// Stage 2 feature: real deletion requires a service-role edge function
  /// (the anon key must never delete users). The client method calls
  /// `rpc('delete_account')` so the SQL function can be added later without
  /// a client change; until it exists the call fails and this returns a
  /// graceful [Failure] — it never throws.
  Future<Result<void>> deleteAccount() => _guard(
        _api.deleteAccount,
        fallbackMessage: 'Account deletion is not available yet.',
      );

  /// Session changes; a null session means signed out.
  Stream<Session?> get sessionStream => _api.sessionStream;

  /// The active session, or null when signed out.
  Session? get currentSession => _api.currentSession;

  Future<Result<T>> _guard<T>(
    Future<T> Function() run, {
    required String fallbackMessage,
  }) async {
    try {
      return Result<T>.success(await run());
    } on AuthException catch (error) {
      return Result<T>.err(
        Failure.unknown(message: error.message, cause: error),
      );
    } catch (error) {
      return Result<T>.err(
        Failure.unknown(message: fallbackMessage, cause: error),
      );
    }
  }
}

/// Feature-scoped binding (Stage 1.2 conventions: providers live inside the
/// feature; tests override with `AuthRepository(FakeAuthApi(...))`).
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseAuthApiProvider)),
);

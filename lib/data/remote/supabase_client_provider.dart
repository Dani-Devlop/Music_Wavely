import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wavely/core/config/env.dart';

/// Storage key the serialized Supabase session JSON is persisted under.
const String kSupabaseSessionStorageKey = 'wavely.supabase.session';

/// Abstracts where the serialized session blob lives (SEC-1 fix).
abstract class _SessionStore {
  Future<String?> read();

  Future<void> write(String value);

  Future<void> delete();
}

/// Mobile / desktop backend: encrypted keychain / keystore via
/// flutter_secure_storage (already a direct dependency).
class _SecureSessionStore implements _SessionStore {
  const _SecureSessionStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: kSupabaseSessionStorageKey);

  @override
  Future<void> write(String value) =>
      _storage.write(key: kSupabaseSessionStorageKey, value: value);

  @override
  Future<void> delete() => _storage.delete(key: kSupabaseSessionStorageKey);
}

/// Web backend: flutter_secure_storage has no web implementation, so the
/// session falls back to SharedPreferences (localStorage in the browser).
class _PrefsSessionStore implements _SessionStore {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> read() async =>
      (await _prefs).getString(kSupabaseSessionStorageKey);

  @override
  Future<void> write(String value) async =>
      (await _prefs).setString(kSupabaseSessionStorageKey, value);

  @override
  Future<void> delete() async => (await _prefs)
      .remove(kSupabaseSessionStorageKey);
}

/// Chooses the platform-appropriate backend at client construction.
_SessionStore defaultSessionStore() =>
    kIsWeb ? _PrefsSessionStore() : const _SecureSessionStore();

/// Attaches session persistence to a bare [SupabaseClient] (SEC-1 fix).
///
/// The app deliberately constructs a plain `SupabaseClient` instead of going
/// through `Supabase.initialize()`, which means supabase_flutter's built-in
/// `SupabaseAuth` persistence layer (LocalStorage + recover-on-boot) never
/// runs and sessions lived in memory only. This reproduces that behavior on
/// top of the public gotrue API — verified against gotrue 2.27.3 /
/// supabase 2.16.5 sources:
///
/// 1. Recover: a stored session JSON is replayed through
///    `auth.recoverSession()` (expired refresh tokens are refreshed by
///    gotrue itself; a corrupt blob is dropped, never thrown).
/// 2. Persist: `signedIn` / `tokenRefreshed` / `initialSession` events write
///    the session JSON through the store; `signedOut` deletes it.
///
/// Returns the auth-state subscription so the caller can tie its lifetime to
/// the provider (canceled on dispose).
StreamSubscription<AuthState> attachSessionPersistence(
  SupabaseClient client, {
  _SessionStore? store,
}) {
  final sessionStore = store ?? defaultSessionStore();

  // Fire-and-forget recovery: the provider is synchronous, but a restored
  // session lands as soon as storage answers. Failures degrade to
  // signed-out (the exact pre-fix behavior) — never break construction.
  unawaited(() async {
    try {
      final stored = await sessionStore.read();
      if (stored == null || stored.isEmpty) {
        return;
      }
      await client.auth.recoverSession(stored);
    } on Object catch (_) {
      try {
        await sessionStore.delete();
      } on Object catch (_) {
        // Best effort only — the next sign-in overwrites the blob anyway.
      }
    }
  }());

  return client.auth.onAuthStateChange.listen((state) {
    final event = state.event;
    final session = state.session;
    if (event == AuthChangeEvent.signedIn ||
        event == AuthChangeEvent.tokenRefreshed ||
        event == AuthChangeEvent.initialSession) {
      if (session != null) {
        unawaited(sessionStore.write(jsonEncode(session.toJson())));
      }
    } else if (event == AuthChangeEvent.signedOut) {
      unawaited(sessionStore.delete());
    }
  });
}

/// Pure-Dart Supabase client built from the compile-time env values.
///
/// Deliberately constructs a [SupabaseClient] directly (the class exported by
/// `supabase_flutter` via `package:supabase/supabase.dart`) instead of using
/// the `Supabase.instance` singleton, so providers stay constructible and
/// overridable without Flutter bindings or `await Supabase.initialize(...)`.
///
/// Stage 3 audit (BUG-3): this client is now ALSO the sync engine's client
/// (see `syncBackendProvider`) so a signed-in session carries into RLS-
/// locked sync requests.
///
/// Stage 3 final polish (SEC-1 fixed): sessions persist across app restarts
/// through [attachSessionPersistence] — flutter_secure_storage on
/// mobile/desktop, SharedPreferences on web. The recovered session also
/// keeps the sync engine authenticated across restarts.
///
/// Throws [StateError] when Supabase is not configured — feature code must
/// check [authEnabledProvider] (production: `WavelyEnv.hasSupabase`) BEFORE
/// watching this provider.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  if (!WavelyEnv.hasSupabase) {
    throw StateError(
      'SUPABASE_URL/SUPABASE_ANON_KEY missing — auth disabled',
    );
  }
  final client = SupabaseClient(WavelyEnv.supabaseUrl!,
      WavelyEnv.supabaseAnonKey!);
  final subscription = attachSessionPersistence(client);
  ref.onDispose(subscription.cancel);
  return client;
});

/// Testable seam over `WavelyEnv.hasSupabase`.
///
/// Every auth screen watches this instead of reading the compile-time
/// constant directly; production behavior is identical, while widget tests
/// override it with `overrideWithValue(true)` (dart-defines cannot be set
/// from tests) to exercise the configured flows.
final authEnabledProvider = Provider<bool>((ref) => WavelyEnv.hasSupabase);

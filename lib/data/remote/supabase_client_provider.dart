import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:wavely/core/config/env.dart';

/// Pure-Dart Supabase client built from the compile-time env values.
///
/// Deliberately constructs a [SupabaseClient] directly (the class exported by
/// `supabase_flutter` via `package:supabase/supabase.dart`) instead of using
/// the `Supabase.instance` singleton, so providers stay constructible and
/// overridable without Flutter bindings or `await Supabase.initialize(...)`.
///
/// Stage 3 audit (BUG-3): this client is now ALSO the sync engine's client
/// (see `syncBackendProvider`) so a signed-in session carries into RLS-
/// locked sync requests. Known follow-up (SEC-1, needs SDK to verify): the
/// default auth storage is in-memory — sessions do not survive restart. The
/// owner should pass `authOptions` with a `flutter_secure_storage`-backed
/// `AuthAsyncStorage` adapter once the resolved supabase_auth version's
/// storage interface is confirmed locally.
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
  return SupabaseClient(WavelyEnv.supabaseUrl!, WavelyEnv.supabaseAnonKey!);
});

/// Testable seam over `WavelyEnv.hasSupabase`.
///
/// Every auth screen watches this instead of reading the compile-time
/// constant directly; production behavior is identical, while widget tests
/// override it with `overrideWithValue(true)` (dart-defines cannot be set
/// from tests) to exercise the configured flows.
final authEnabledProvider = Provider<bool>((ref) => WavelyEnv.hasSupabase);

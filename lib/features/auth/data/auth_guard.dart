import 'package:go_router/go_router.dart';

/// Route paths that REQUIRE a signed-in Supabase session. Everything else —
/// library, search, settings root, onboarding, now-playing, the auth screens
/// themselves — stays reachable without an account.
const List<String> protectedRoutePrefixes = <String>[
  '/settings/account',
  '/ai-chat',
];

/// Pure, table-testable go_router redirect core (Stage 1.2, task B3).
///
/// * Supabase configured + unauthenticated + protected path → `/login`.
/// * Supabase NOT configured: auth is a hidden feature — everything is
///   allowed EXCEPT protected paths, which bounce back to `/settings`
///   (feature hidden, never a dead end).
/// * Any public path → null (no redirect).
String? authGuard({
  required bool hasSupabase,
  required bool isAuthenticated,
  required String location,
}) {
  if (!_isProtected(location)) return null;
  if (!hasSupabase) return '/settings';
  if (!isAuthenticated) return '/login';
  return null;
}

/// GoRouter-shaped adapter the orchestrator wires into `router.dart`:
///
/// ```dart
/// GoRouter(
///   // ...
///   redirect: (context, state) => authGuardFromState(
///     state,
///     hasSupabase: WavelyEnv.hasSupabase,
///     // authRepositoryProvider exposes the live session:
///     isAuthenticated: ref.read(authRepositoryProvider).currentSession != null,
///   ),
/// );
/// ```
String? authGuardFromState(
  GoRouterState state, {
  required bool hasSupabase,
  required bool isAuthenticated,
}) =>
    authGuard(
      hasSupabase: hasSupabase,
      isAuthenticated: isAuthenticated,
      location: state.uri.path,
    );

bool _isProtected(String location) {
  final path = Uri.parse(location).path;
  return protectedRoutePrefixes.any(
    (prefix) => path == prefix || path.startsWith('$prefix/'),
  );
}

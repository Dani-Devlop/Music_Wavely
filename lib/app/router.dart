import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wavely/app/main_shell.dart';
import 'package:wavely/features/ai_chat/presentation/ai_chat_screen.dart';
import 'package:wavely/features/analytics/presentation/analytics_screen.dart';
import 'package:wavely/features/analytics/presentation/lifetime_favorites_screen.dart';
import 'package:wavely/features/auth/data/auth_guard.dart';
import 'package:wavely/features/auth/data/auth_repository.dart';
import 'package:wavely/features/auth/presentation/login_screen.dart';
import 'package:wavely/features/auth/presentation/signup_screen.dart';
import 'package:wavely/features/auth/presentation/telegram_login_screen.dart';
import 'package:wavely/features/auth/presentation/welcome_screen.dart';
import 'package:wavely/features/discovery/presentation/discovery_screen.dart';
import 'package:wavely/features/library/presentation/album_detail_screen.dart';
import 'package:wavely/features/library/presentation/artist_detail_screen.dart';
import 'package:wavely/core/config/env.dart';
import 'package:wavely/features/library/presentation/library_screen.dart';
import 'package:wavely/features/onboarding/data/onboarding_repository.dart';
import 'package:wavely/features/onboarding/presentation/onboarding_flow.dart';
import 'package:wavely/features/parental/presentation/parental_screen.dart';
import 'package:wavely/features/player/presentation/now_playing_screen.dart';
import 'package:wavely/features/search/presentation/search_screen.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/features/settings/presentation/settings_screen.dart';

/// Root navigator key shared by the shell and the outside-the-shell
/// now-playing route.
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');

/// App router: 3-branch stateful shell (library incl. nested artist/album
/// details, search, settings) plus fullscreen routes pushed on the ROOT
/// navigator (now-playing with a fade; Stage 1.2 feature screens).
// Manual Provider on purpose: the GoRouter must be constructed once and its
// lifecycle tied to the container; codegen adds nothing here.
final routerProvider = Provider<GoRouter>((ref) {
  // The prefs instance is stable for the app's lifetime (bootstrap
  // override); the redirect closure reads it on every navigation.
  final prefs = ref.watch(sharedPrefsProvider);
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: LibraryScreen.libraryRoute,
    redirect: (context, state) {
      final completed = OnboardingRepository(prefs).isCompleted();
      final onOnboarding = state.matchedLocation == OnboardingFlow.route;
      if (!completed && !onOnboarding) {
        return OnboardingFlow.route;
      }
      if (completed && onOnboarding) {
        return LibraryScreen.libraryRoute;
      }
      // Auth guard: /ai-chat requires a session (library + playback never
      // do). Parental/analytics/discovery stay local-only (no account).
      // `read` (not watch): redirects run per navigation, outside the
      // provider build body.
      final hasSupabase = WavelyEnv.hasSupabase;
      final isAuthenticated = hasSupabase &&
          ref.read(authRepositoryProvider).currentSession != null;
      return authGuardFromState(
        state,
        hasSupabase: hasSupabase,
        isAuthenticated: isAuthenticated,
      );
    },
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: LibraryScreen.libraryRoute,
                builder: (context, state) => const LibraryScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'artist/:name',
                    builder: (context, state) => ArtistDetailScreen(
                      artistName: state.pathParameters['name']!,
                    ),
                  ),
                  GoRoute(
                    path: 'album/:artist/:album',
                    builder: (context, state) => AlbumDetailScreen(
                      artistName: state.pathParameters['artist']!,
                      albumTitle: state.pathParameters['album']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: SearchScreen.route,
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: SettingsScreen.route,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      // -- Fullscreen routes (root navigator) --------------------------------
      GoRoute(
        path: NowPlayingScreen.route,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: const NowPlayingScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      ),
      GoRoute(
        path: OnboardingFlow.route,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const OnboardingFlow(),
      ),
      GoRoute(
        path: WelcomeScreen.route,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: LoginScreen.route,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: SignUpScreen.route,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: TelegramLoginScreen.route,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const TelegramLoginScreen(),
      ),
      GoRoute(
        path: AnalyticsScreen.route,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AnalyticsScreen(),
      ),
      GoRoute(
        path: LifetimeFavoritesScreen.route,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const LifetimeFavoritesScreen(),
      ),
      GoRoute(
        path: DiscoveryScreen.route,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const DiscoveryScreen(),
      ),
      GoRoute(
        path: AiChatScreen.route,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AiChatScreen(),
      ),
      GoRoute(
        path: ParentalScreen.route,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ParentalScreen(),
      ),
    ],
  );
});

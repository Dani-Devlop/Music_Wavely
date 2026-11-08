import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wavely/app/main_shell.dart';
import 'package:wavely/core/config/env.dart';
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
import 'package:wavely/features/audio_cutter/presentation/audio_cutter_screen.dart';
import 'package:wavely/features/downloads/presentation/download_settings_screen.dart';
import 'package:wavely/features/downloads/presentation/downloads_screen.dart';
import 'package:wavely/features/home/presentation/home_screen.dart';
import 'package:wavely/features/library/presentation/album_detail_screen.dart';
import 'package:wavely/features/library/presentation/artist_detail_screen.dart';
import 'package:wavely/features/library/presentation/library_screen.dart';
import 'package:wavely/features/news/presentation/news_screen.dart';
import 'package:wavely/features/news/presentation/news_settings_screen.dart';
import 'package:wavely/features/onboarding/data/onboarding_repository.dart';
import 'package:wavely/features/onboarding/presentation/onboarding_flow.dart';
import 'package:wavely/features/online/presentation/online_screen.dart';
import 'package:wavely/features/parental/presentation/parental_screen.dart';
import 'package:wavely/features/player/presentation/now_playing_screen.dart';
import 'package:wavely/features/player/presentation/now_playing_tab.dart';
import 'package:wavely/features/search/presentation/search_hub_shell.dart';
import 'package:wavely/features/search/presentation/search_screen.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/features/settings/presentation/screens/audio_settings_screen.dart';
import 'package:wavely/features/settings/presentation/screens/update_screen.dart';
import 'package:wavely/features/tag_editor/presentation/tag_editor_screen.dart';
import 'package:wavely/features/settings/presentation/settings_screen.dart';

/// Root navigator key shared by the shell and the outside-the-shell
/// now-playing route.
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');

/// App router: 4-branch stateful shell (playlist home, now playing,
/// search hub hosting the local library + online discovery, settings) plus
/// fullscreen routes pushed on the ROOT navigator (now-playing with a
/// fade; Stage 1.2 feature screens).
///
/// v1.0.1-beta3 parity spec: exactly four bottom tabs. The former Local
/// and Online branches live inside the Search branch under a
/// [SearchHubShell] (persistent Search · Library · Online chip row) — the
/// `/local`, `/local/artist/:name`, `/local/album/:artist/:album` and
/// `/online` paths are unchanged for deep links and tests.
// Manual Provider on purpose: the GoRouter must be constructed once and its
// lifecycle tied to the container; codegen adds nothing here.
final routerProvider = Provider<GoRouter>((ref) {
  // The prefs instance is stable for the app's lifetime (bootstrap
  // override); the redirect closure reads it on every navigation.
  final prefs = ref.watch(sharedPrefsProvider);
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: HomeScreen.route,
    redirect: (context, state) {
      final completed = OnboardingRepository(prefs).isCompleted();
      final onOnboarding = state.matchedLocation == OnboardingFlow.route;
      if (!completed && !onOnboarding) {
        return OnboardingFlow.route;
      }
      if (completed && onOnboarding) {
        return HomeScreen.route;
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
          // ── Tab 1 · Playlist (Home) ────────────────────────────────────
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: HomeScreen.route,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          // ── Tab 2 · Now Playing (full player, embedded) ────────────────
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: NowPlayingTab.route,
                builder: (context, state) => const NowPlayingTab(),
              ),
            ],
          ),
          // ── Tab 3 · Search (hub: unified search + Library + Online) ────
          StatefulShellBranch(
            routes: <RouteBase>[
              ShellRoute(
                builder: (context, state, child) => SearchHubShell(
                  location: state.matchedLocation,
                  child: child,
                ),
                routes: <RouteBase>[
                  GoRoute(
                    path: SearchScreen.route,
                    builder: (context, state) => const SearchScreen(),
                  ),
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
                  GoRoute(
                    path: OnlineScreen.route,
                    builder: (context, state) => const OnlineScreen(),
                  ),
                ],
              ),
            ],
          ),
          // ── Tab 4 · Settings ───────────────────────────────────────────
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
      // -- Stage 2.1: downloads -------------------------------------------
      GoRoute(
        path: downloadsRoute,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const DownloadsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'settings',
            parentNavigatorKey: rootNavigatorKey,
            builder: (context, state) => const DownloadSettingsScreen(),
          ),
        ],
      ),
      // -- Stage 2.2: news --------------------------------------------------
      GoRoute(
        path: newsRoute,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const NewsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'settings',
            parentNavigatorKey: rootNavigatorKey,
            builder: (context, state) => const NewsSettingsScreen(),
          ),
        ],
      ),
      // -- Stage 7: in-app update flow --------------------------------------
      GoRoute(
        path: UpdateScreen.route,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const UpdateScreen(),
      ),
      // -- Phase 7: tag editor & audio cutter --------------------------------
      GoRoute(
        path: kTagEditorRoute,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final Object? extra = state.extra;
          final List<String> paths = extra is List<Object?>
              ? extra.whereType<String>().toList(growable: false)
              : const <String>[];
          return TagEditorScreen(filePaths: paths);
        },
      ),
      GoRoute(
        path: kAudioCutterRoute,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => AudioCutterScreen(
          sourcePath: (state.extra as String?) ?? '',
        ),
      ),
      // -- Phase 8: equalizer & effects ---------------------------------------
      GoRoute(
        path: kAudioSettingsRoute,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AudioSettingsScreen(),
      ),
    ],
  );
});

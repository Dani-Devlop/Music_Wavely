/// Authored, awaiting local run (Task 2-a).
///
/// Route-table integrity tests for `lib/app/router.dart`.
///
/// Two layers:
/// 1. CONFIGURATION — the [routerProvider] is built exactly as the app
///    does (inside a ProviderContainer with `sharedPrefsProvider` pointed
///    at mock prefs) and its `GoRouter.configuration` is walked to assert
///    the full path table, the initial location and the 3-branch shell.
/// 2. BEHAVIOR — the REAL WavelyApp is pumped through the pump_app harness
///    and the onboarding redirect (`wavely.onboarding.completed` → wizard
///    vs library) plus the no-Supabase auth-guard bounce (`/ai-chat` →
///    `/settings`) are exercised end-to-end.
///
/// `WavelyEnv.hasSupabase` is a compile-time constant that is false in
/// `flutter test` builds, which is exactly the state the guard tests want.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/app/router.dart';
import 'package:wavely/features/ai_chat/presentation/ai_chat_screen.dart';
import 'package:wavely/features/analytics/presentation/analytics_screen.dart';
import 'package:wavely/features/analytics/presentation/lifetime_favorites_screen.dart';
import 'package:wavely/features/auth/presentation/login_screen.dart';
import 'package:wavely/features/auth/presentation/signup_screen.dart';
import 'package:wavely/features/auth/presentation/telegram_login_screen.dart';
import 'package:wavely/features/auth/presentation/welcome_screen.dart';
import 'package:wavely/features/discovery/presentation/discovery_screen.dart';
import 'package:wavely/features/library/presentation/library_screen.dart';
import 'package:wavely/features/onboarding/data/onboarding_state.dart';
import 'package:wavely/features/onboarding/presentation/onboarding_flow.dart';
import 'package:wavely/features/parental/presentation/parental_screen.dart';
import 'package:wavely/features/player/presentation/now_playing_screen.dart';
import 'package:wavely/features/search/presentation/search_screen.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/features/settings/presentation/settings_screen.dart';

import 'pump_app.dart';

/// Collects every concrete GoRoute path from the configuration tree.
Set<String> collectPaths(List<RouteBase> routes, {String parent = ''}) {
  final paths = <String>{};
  for (final route in routes) {
    switch (route) {
      case final GoRoute goRoute:
        final full =
            parent.isEmpty ? goRoute.path : '$parent/${goRoute.path}';
        paths.add(full);
        paths.addAll(collectPaths(goRoute.routes, parent: full));
      case final StatefulShellRoute shell:
        for (final branch in shell.branches) {
          paths.addAll(collectPaths(branch.routes, parent: parent));
        }
      case final ShellRoute shell:
        paths.addAll(collectPaths(shell.routes, parent: parent));
    }
  }
  return paths;
}

Future<ProviderContainer> configContainer() async {
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: <Override>[sharedPrefsProvider.overrideWithValue(prefs)],
  );
}

void main() {
  group('router configuration', () {
    test('initial location is the library route', () async {
      final container = await configContainer();
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      expect(router.initialLocation, LibraryScreen.libraryRoute);
    });

    test('route table contains exactly the registered paths', () async {
      final container = await configContainer();
      addTearDown(container.dispose);
      final router = container.read(routerProvider);

      final expected = <String>{
        // Shell branches.
        LibraryScreen.libraryRoute,
        '${LibraryScreen.libraryRoute}/artist/:name',
        '${LibraryScreen.libraryRoute}/album/:artist/:album',
        SearchScreen.route,
        SettingsScreen.route,
        // Root-navigator fullscreen routes.
        NowPlayingScreen.route,
        OnboardingFlow.route,
        WelcomeScreen.route,
        LoginScreen.route,
        SignUpScreen.route,
        TelegramLoginScreen.route,
        AnalyticsScreen.route,
        LifetimeFavoritesScreen.route,
        DiscoveryScreen.route,
        AiChatScreen.route,
        ParentalScreen.route,
      };

      final actual =
          collectPaths(router.configuration.routes);
      expect(actual, equals(expected));
    });

    test('the stateful shell owns exactly three branches', () async {
      final container = await configContainer();
      addTearDown(container.dispose);
      final router = container.read(routerProvider);

      final shells = router.configuration.routes
          .whereType<StatefulShellRoute>()
          .toList();
      expect(shells, hasLength(1));
      expect(shells.single.branches, hasLength(3));
    });

    test('library detail routes are nested under the library branch',
        () async {
      final container = await configContainer();
      addTearDown(container.dispose);
      final router = container.read(routerProvider);

      final paths = collectPaths(router.configuration.routes);
      expect(
        paths,
        containsAll(<String>[
          '${LibraryScreen.libraryRoute}/artist/:name',
          '${LibraryScreen.libraryRoute}/album/:artist/:album',
        ]),
      );
    });

    test('fullscreen routes are registered at the root (not the shell)',
        () async {
      final container = await configContainer();
      addTearDown(container.dispose);
      final router = container.read(routerProvider);

      final rootPaths = router.configuration.routes
          .whereType<GoRoute>()
          .map((r) => r.path)
          .toSet();
      expect(rootPaths, contains(NowPlayingScreen.route));
      expect(rootPaths, contains(AiChatScreen.route));
      expect(rootPaths, contains(OnboardingFlow.route));
      // Branch-only paths must NOT appear at the root level.
      expect(rootPaths, isNot(contains(LibraryScreen.libraryRoute)));
    });
  });

  group('router redirects (pumped through the real WavelyApp)', () {
    testWidgets('incomplete onboarding redirects the app into the wizard',
        (tester) async {
      final harness = await pumpWavelyApp(tester);
      addTearDown(harness.tearDown);

      expect(find.byType(OnboardingFlow), findsOneWidget);
      expect(find.byType(LibraryScreen), findsNothing);
    });

    testWidgets('completed onboarding boots into the library shell',
        (tester) async {
      final harness = await pumpWavelyApp(
        tester,
        onboardingCompleted: true,
      );
      addTearDown(harness.tearDown);

      expect(find.byType(OnboardingFlow), findsNothing);
      expect(find.byType(LibraryScreen), findsOneWidget);
    });

    testWidgets('completing onboarding + refresh moves wizard → library',
        (tester) async {
      final harness = await pumpWavelyApp(tester);
      addTearDown(harness.tearDown);
      expect(find.byType(OnboardingFlow), findsOneWidget);

      // The wizard's Finish step writes this key; simulate it and make the
      // router re-run its redirect.
      await harness.prefs.setString(OnboardingDraft.prefsCompletedKey, 'true');
      harness.container.read(routerProvider).refresh();
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingFlow), findsNothing);
      expect(find.byType(LibraryScreen), findsOneWidget);
    });

    testWidgets('without Supabase, /ai-chat bounces back to /settings',
        (tester) async {
      final harness = await pumpWavelyApp(
        tester,
        onboardingCompleted: true,
      );
      addTearDown(harness.tearDown);
      expect(find.byType(LibraryScreen), findsOneWidget);

      harness.container.read(routerProvider).go(AiChatScreen.route);
      await tester.pumpAndSettle();

      expect(find.byType(AiChatScreen), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });
}

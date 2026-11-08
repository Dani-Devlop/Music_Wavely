/// Authored, awaiting local run (Task 2-a).
///
/// Widget tests for `lib/app/main_shell.dart` pumped through the REAL
/// WavelyApp (pump_app harness): real router → real `MainShell` around the
/// stateful navigation shell, with the in-memory drift db, mock prefs and
/// the fake playback engine.
///
/// v1.0.1-beta3 parity spec: the shell has EXACTLY FOUR destinations
/// (Playlist / Now Playing / Search / Settings); the local library and the
/// online discovery live inside the Search branch (SearchHubShell).
///
/// Covered:
/// - The four glass bottom-nav destinations render with their labels.
/// - Tapping a destination switches the branch (HomeScreen /
///   NowPlayingTab / SearchScreen / SettingsScreen).
/// - The Search hub chips switch between the unified search, the local
///   library (LibraryScreen) and the online pane (OnlineScreen) inside
///   the same branch.
/// - Once a track is queued through the real `queueManagerProvider`, the
///   mini player host slides in (`mini-player` key) and the fake engine
///   received the load call — wiring the shell → queue → engine chain
///   without any platform channel.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/home/presentation/home_screen.dart';
import 'package:wavely/features/library/presentation/library_screen.dart';
import 'package:wavely/features/online/presentation/online_screen.dart';
import 'package:wavely/features/player/presentation/mini_player_widget.dart';
import 'package:wavely/features/player/presentation/now_playing_tab.dart';
import 'package:wavely/features/search/presentation/search_screen.dart';
import 'package:wavely/features/settings/presentation/settings_screen.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

import '../support/track_factory.dart';
import 'pump_app.dart';

void main() {
  group('MainShell bottom navigation', () {
    testWidgets('renders exactly the four destinations over the home branch',
        (tester) async {
      final harness = await pumpWavelyApp(tester, onboardingCompleted: true);
      addTearDown(harness.tearDown);

      // The app boots into the Playlist branch (empty library → empty state).
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Playlist'), findsOneWidget);
      expect(find.text('Now Playing'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      // No track queued → mini player collapsed.
      expect(find.byType(MiniPlayerWidget), findsNothing);
    });

    testWidgets('tapping Now Playing switches to the player branch',
        (tester) async {
      final harness = await pumpWavelyApp(tester, onboardingCompleted: true);
      addTearDown(harness.tearDown);

      await tester.tap(find.text('Now Playing'));
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingTab), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      // Empty queue → the branded empty state with the funnel CTA.
      expect(find.text('Nothing playing'), findsOneWidget);
    });

    testWidgets('tapping Search switches to the search branch',
        (tester) async {
      final harness = await pumpWavelyApp(tester, onboardingCompleted: true);
      addTearDown(harness.tearDown);

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      // The nav bar persists across branches.
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('tapping Settings switches to the settings branch',
        (tester) async {
      final harness = await pumpWavelyApp(tester, onboardingCompleted: true);
      addTearDown(harness.tearDown);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      // AppBar title + nav destination.
      expect(find.text('Settings'), findsNWidgets(2));
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('the Search hub chips host Library and Online in-branch',
        (tester) async {
      final harness = await pumpWavelyApp(tester, onboardingCompleted: true);
      addTearDown(harness.tearDown);

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      // Hub chip → the local library (former Local tab).
      await tester.tap(find.byKey(const Key('hub-chip-local')));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryScreen), findsOneWidget);

      // Hub chip → the online pane (former Online tab).
      await tester.tap(find.byKey(const Key('hub-chip-online')));
      await tester.pumpAndSettle();
      expect(find.byType(OnlineScreen), findsOneWidget);

      // Back to the unified search.
      await tester.tap(find.byKey(const Key('hub-chip-search')));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('tapping Playlist returns to the home branch', (tester) async {
      final harness = await pumpWavelyApp(tester, onboardingCompleted: true);
      addTearDown(harness.tearDown);

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);

      await tester.tap(find.text('Playlist'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(SearchScreen), findsNothing);
    });
  });

  group('MainShell mini player', () {
    testWidgets('queues a track through QueueManager and shows the mini '
        'player backed by the fake engine', (tester) async {
      final harness = await pumpWavelyApp(tester, onboardingCompleted: true);
      addTearDown(harness.tearDown);

      expect(find.byKey(const ValueKey<String>('mini-player')), findsNothing);

      await harness.container
          .read(queueManagerProvider.notifier)
          .setQueue(seedTracks(1));
      await tester.pumpAndSettle();

      // Mini player host now renders the track row.
      expect(find.byKey(const ValueKey<String>('mini-player')), findsOneWidget);
      expect(find.byType(MiniPlayerWidget), findsOneWidget);

      // The engine override received the load exactly as QueueManager
      // issues it (single-track loaders → setQueue(tracks, startIndex)).
      expect(harness.engine.setQueueCalls, 1);
      expect(harness.engine.lastSetQueue, hasLength(1));
      expect(harness.engine.lastSetQueue.single.title, 'Track 1');
      expect(harness.engine.lastStartIndex, 0);
    });

    testWidgets('play() on the queued track reaches the fake engine',
        (tester) async {
      final harness = await pumpWavelyApp(tester, onboardingCompleted: true);
      addTearDown(harness.tearDown);

      final manager = harness.container.read(queueManagerProvider.notifier);
      await manager.setQueue(seedTracks(1));
      await tester.pumpAndSettle();
      expect(harness.engine.playCalls, 0, reason: 'paused load records none');

      await manager.play();
      await tester.pumpAndSettle();

      expect(harness.engine.playCalls, 1);
    });

    testWidgets('the Now Playing tab shows the queued track',
        (tester) async {
      final harness = await pumpWavelyApp(tester, onboardingCompleted: true);
      addTearDown(harness.tearDown);

      await harness.container
          .read(queueManagerProvider.notifier)
          .setQueue(seedTracks(1));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Now Playing'));
      await tester.pumpAndSettle();

      // The full player renders inline in the tab for the queued track
      // (the mini player below the bar shows the same title).
      expect(find.byType(NowPlayingTab), findsOneWidget);
      expect(find.text('Track 1'), findsWidgets);
    });
  });
}

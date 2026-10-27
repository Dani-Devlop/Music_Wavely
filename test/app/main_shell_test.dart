/// Authored, awaiting local run (Task 2-a).
///
/// Widget tests for `lib/app/main_shell.dart` pumped through the REAL
/// WavelyApp (pump_app harness): real router → real `MainShell` around the
/// stateful navigation shell, with the in-memory drift db, mock prefs and
/// the fake playback engine.
///
/// Covered:
/// - The three glass bottom-nav destinations (Library / Search / Settings)
///   render with their labels.
/// - Tapping a destination switches the branch (SearchScreen /
///   SettingsScreen / back to LibraryScreen).
/// - Once a track is queued through the real `queueManagerProvider`, the
///   mini player host slides in (`mini-player` key) and the fake engine
///   received the load call — wiring the shell → queue → engine chain
///   without any platform channel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/library/presentation/library_screen.dart';
import 'package:wavely/features/player/presentation/mini_player_widget.dart';
import 'package:wavely/features/search/presentation/search_screen.dart';
import 'package:wavely/features/settings/presentation/settings_screen.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

import '../support/track_factory.dart';
import 'pump_app.dart';

void main() {
  group('MainShell bottom navigation', () {
    testWidgets('renders the three destinations over the library branch',
        (tester) async {
      final harness = await pumpWavelyApp(tester, onboardingCompleted: true);
      addTearDown(harness.tearDown);

      // Library label appears twice: nav destination + screen header.
      expect(find.text('Library'), findsNWidgets(2));
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.byType(LibraryScreen), findsOneWidget);
      // No track queued → mini player collapsed.
      expect(find.byType(MiniPlayerWidget), findsNothing);
    });

    testWidgets('tapping Search switches to the search branch',
        (tester) async {
      final harness = await pumpWavelyApp(tester, onboardingCompleted: true);
      addTearDown(harness.tearDown);

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsOneWidget);
      expect(find.byType(LibraryScreen), findsNothing);
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

    testWidgets('tapping Library returns to the library branch',
        (tester) async {
      final harness = await pumpWavelyApp(tester, onboardingCompleted: true);
      addTearDown(harness.tearDown);

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);

      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryScreen), findsOneWidget);
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
  });
}

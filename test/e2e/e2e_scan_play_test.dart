/// Stage 6 E2E — ARTEMIS Scenario 1: "Open Wavely, add a music folder from
/// the library screen, scan it, and play the first song. Verify the
/// mini-player appears and the song is playing."
///
/// The REAL [WavelyApp] boots through the real router and the real
/// [QueueManager] / `QueueTrackLauncher` playback bridge; the only fakes
/// are the hermetic ones every widget test already uses (in-memory Drift,
/// mock SharedPreferences, [FakePlaybackEngine], idle sync engine) plus a
/// scripted [LibraryScanner] that mirrors what the real `ScanLibrary`
/// usecase does — parse files → insert track rows → emit scan events —
/// without the filesystem walker.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavely/app/wavely_app.dart' show WavelyApp;
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/library_scanner.dart' show LibraryScanner;
import 'package:wavely/features/library/data/library_scanner_provider.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

import '../app/pump_app.dart';
import '../features/library/fakes.dart'
    show FakeLibraryScanner, seedCompanion;
import '../support/fake_playback_engine.dart' show FakePlaybackEngine;

/// Scanner fake that seeds the SAME database the app runs on (what the
/// real `ScanLibrary` usecase does when it walks picked folders) and then
/// replays a started/completed event pair.
class _SeedingScanner extends FakeLibraryScanner {
  _SeedingScanner({
    required this.db,
    required this.tracks,
    required String pickedRoot,
  }) : super(
          picked: <String>[pickedRoot],
          events: <ScanEvent>[
            ScanEvent.scanStarted(root: pickedRoot),
            ScanEvent.completed(
              count: tracks.length,
              errors: const <String>[],
            ),
          ],
        );

  final AppDatabase db;
  final List<TracksCompanion> tracks;

  /// Replays what the real scanner pipeline does: insert every parsed
  /// track into the library database, then stream the scan lifecycle.
  @override
  Stream<ScanEvent> scan(List<String> folders) async* {
    scanCalls++;
    scannedFolders.add(List<String>.of(folders));
    for (final track in tracks) {
      await db.tracksDao.insertTrack(track);
    }
    yield* Stream<ScanEvent>.fromIterable(events);
  }
}

void main() {
  testWidgets('scan → library populated → first song plays with the '
      'mini-player visible and in the playing state', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());

    const titles = <String>[
      'Neon Rivers',
      'Glass Harbour',
      'Northbound',
      'Afterglow',
    ];
    final scanner = _SeedingScanner(
      db: db,
      pickedRoot: '/music',
      tracks: <TracksCompanion>[
        seedCompanion(title: titles[0], artist: 'Velvet Echo'),
        seedCompanion(title: titles[1], artist: 'Cedar Waves'),
        seedCompanion(title: titles[2], artist: 'Velvet Echo'),
        seedCompanion(title: titles[3], artist: 'Cedar Waves'),
      ],
    );

    final harness = await pumpWavelyApp(
      tester,
      onboardingCompleted: true,
      db: db,
      extraOverrides: <Override>[
        libraryScannerProvider.overrideWithValue(scanner),
      ],
    );
    addTearDown(harness.tearDown);

    // ── 1. Add a music folder from the Folders tab ───────────────────────
    // The app boots into the Home branch; switch to the Local branch, then
    // to the Folders tab (Phase 6 opens the library on Songs).
    await tester.tap(find.text('Local'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Folders'));
    await tester.pumpAndSettle();
    final addFolder = find.widgetWithText(FilledButton, 'Add folder');
    expect(addFolder, findsWidgets);
    await tester.tap(addFolder.first);
    await tester.pumpAndSettle();

    // The scanner was asked to scan the merged folder list.
    expect(scanner.scannedFolders, <List<String>>[<String>['/music']]);
    expect(scanner.scanCalls, 1);

    // ── 2. The scan populated the library ───────────────────────────────
    // Selecting Folders (5th of 9 tabs) scrolled the bar; bring Songs back.
    await tester.fling(find.byType(TabBar), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Songs'));
    await tester.pumpAndSettle();
    for (final title in titles) {
      expect(find.text(title), findsOneWidget, reason: title);
    }

    // ── 3. Play the first song ───────────────────────────────────────────
    await tester.tap(find.text(titles[0]));
    await tester.pumpAndSettle();

    expect(harness.engine.setQueueCalls, 1);
    expect(harness.engine.playCalls, 1);
    expect(harness.engine.loadedTrack?.title, titles[0]);
    expect(
      harness.container.read(queueManagerProvider).playbackState,
      PlaybackState.playing,
    );

    // ── 4. The mini-player appears and shows the playing track ──────────
    expect(find.byKey(const ValueKey<String>('mini-player')), findsOneWidget);
    // The title is visible twice: once in the All Tracks tile, once in the
    // mini-player.
    expect(find.text(titles[0]), findsNWidgets(2));
    // Playing state renders the pause affordance in the mini-player.
    expect(find.byTooltip('Pause'), findsOneWidget);
  });
}

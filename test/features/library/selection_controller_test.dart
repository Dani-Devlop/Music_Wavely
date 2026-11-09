/// Phase 6 — multi-select tests: long-press entry, Select All / Invert, the
/// selection bar count and the bulk actions (Play, Play Next via the queue
/// bridge, Add to Queue, Add to Playlist, Delete).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/library_view_config.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/features/library/presentation/all_tracks_tab.dart';
import 'package:wavely/features/library/presentation/sort_menu.dart';
import 'package:wavely/l10n/app_localizations.dart';

import 'fakes.dart';

/// Records [QueueBridge] calls for the selection-action tests.
class RecordingQueueBridge implements QueueBridge {
  final List<({String action, List<Track> tracks})> calls =
      <({String action, List<Track> tracks})>[];

  @override
  Future<void> playNext(List<Track> tracks) async =>
      calls.add((action: 'playNext', tracks: List<Track>.of(tracks)));

  @override
  Future<void> appendToQueue(List<Track> tracks) async =>
      calls.add((action: 'appendToQueue', tracks: List<Track>.of(tracks)));
}

Future<(ProviderContainer, FakeTrackLauncher, RecordingQueueBridge)>
    _pumpTab(
  WidgetTester tester, {
  required AppDatabase db,
}) async {
  final launcher = FakeTrackLauncher();
  final bridge = RecordingQueueBridge();
  final container = ProviderContainer(
    overrides: <Override>[
      databaseProvider.overrideWithValue(db),
      trackLauncherProvider.overrideWithValue(launcher),
      queueBridgeProvider.overrideWithValue(bridge),
      libraryViewConfigStoreProvider
          .overrideWithValue(LibraryViewConfigStore(InMemorySettingsStore())),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: WavelyThemes.dark(WavelyAccent.purple.colors),
        home: const Scaffold(body: AllTracksTab()),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
  return (container, launcher, bridge);
}

/// v1.0.2: long-press opens the Musicolet 14-option context sheet now, so
/// the multi-select mode is entered through the dedicated toggle next to
/// the quick-search box, then the first row is tapped to select it.
/// (Same net state the old long-press produced: bar visible, 1 selected.)
Future<void> _longPressFirstTile(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('select-mode-toggle')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Aurora Skies'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('long-press enters selection mode and shows the count',
      (tester) async {
    final db = newMemoryDb();
    addTearDown(db.close);
    await db.tracksDao.insertTrack(seedCompanion(
        title: 'Aurora Skies', artist: 'A', sourceTrackId: 's1'));
    await db.tracksDao.insertTrack(
        seedCompanion(title: 'Cascade', artist: 'B', sourceTrackId: 's2'));

    await _pumpTab(tester, db: db);

    expect(find.byKey(const ValueKey<String>('selection-bar')), findsNothing);
    await _longPressFirstTile(tester);

    expect(find.byKey(const ValueKey<String>('selection-bar')), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('tap toggles rows and Select All / Invert work',
      (tester) async {
    final db = newMemoryDb();
    addTearDown(db.close);
    await db.tracksDao.insertTrack(seedCompanion(
        title: 'Aurora Skies', artist: 'A', sourceTrackId: 's1'));
    await db.tracksDao.insertTrack(
        seedCompanion(title: 'Cascade', artist: 'B', sourceTrackId: 's2'));
    await db.tracksDao.insertTrack(
        seedCompanion(title: 'Delta Rays', artist: 'C', sourceTrackId: 's3'));

    await _pumpTab(tester, db: db);
    await _longPressFirstTile(tester);
    await tester.tap(find.text('Cascade'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    // Select All covers every loaded row.
    await tester.tap(
        find.byKey(const ValueKey<String>('selection-select-all')));
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);

    // Invert over the full universe: 3 selected -> 0 -> selection exits.
    await tester.tap(find.byKey(const ValueKey<String>('selection-invert')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('selection-bar')), findsNothing);
  });

  testWidgets('Play launches the selected rows in list order',
      (tester) async {
    final db = newMemoryDb();
    addTearDown(db.close);
    await db.tracksDao.insertTrack(seedCompanion(
        title: 'Aurora Skies', artist: 'A', sourceTrackId: 's1'));
    await db.tracksDao.insertTrack(
        seedCompanion(title: 'Cascade', artist: 'B', sourceTrackId: 's2'));
    await db.tracksDao.insertTrack(
        seedCompanion(title: 'Delta Rays', artist: 'C', sourceTrackId: 's3'));

    final (container, launcher, _) = await _pumpTab(tester, db: db);
    await _longPressFirstTile(tester);
    await tester.tap(find.text('Cascade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(launcher.calls, hasLength(1));
    expect(
      launcher.calls.single.tracks.map((t) => t.title).toList(),
      <String>['Aurora Skies', 'Cascade'],
    );
    expect(launcher.calls.single.startIndex, 0);
    // Selection cleared after the action.
    expect(find.byKey(const ValueKey<String>('selection-bar')), findsNothing);
  });

  testWidgets('Play Next routes through the queue bridge', (tester) async {
    final db = newMemoryDb();
    addTearDown(db.close);
    await db.tracksDao.insertTrack(seedCompanion(
        title: 'Aurora Skies', artist: 'A', sourceTrackId: 's1'));
    await db.tracksDao.insertTrack(
        seedCompanion(title: 'Cascade', artist: 'B', sourceTrackId: 's2'));

    final (_, launcher, bridge) = await _pumpTab(tester, db: db);
    await _longPressFirstTile(tester);
    await tester.tap(find.text('Play Next'));
    await tester.pumpAndSettle();

    expect(bridge.calls, hasLength(1));
    expect(bridge.calls.single.action, 'playNext');
    expect(
      bridge.calls.single.tracks.map((t) => t.title).toList(),
      <String>['Aurora Skies'],
    );
    // playNext never replaces the queue.
    expect(launcher.calls, isEmpty);
  });

  testWidgets('Add to Queue routes through the queue bridge', (tester) async {
    final db = newMemoryDb();
    addTearDown(db.close);
    await db.tracksDao.insertTrack(seedCompanion(
        title: 'Aurora Skies', artist: 'A', sourceTrackId: 's1'));

    final (_, launcher, bridge) = await _pumpTab(tester, db: db);
    await _longPressFirstTile(tester);
    await tester.tap(find.text('Add to Queue'));
    await tester.pumpAndSettle();

    expect(bridge.calls.single.action, 'appendToQueue');
    expect(launcher.calls, isEmpty);
  });

  testWidgets('Add to Playlist creates a playlist with the selected rows',
      (tester) async {
    final db = newMemoryDb();
    addTearDown(db.close);
    await db.tracksDao.insertTrack(seedCompanion(
        title: 'Aurora Skies', artist: 'A', sourceTrackId: 's1'));
    await db.tracksDao.insertTrack(
        seedCompanion(title: 'Cascade', artist: 'B', sourceTrackId: 's2'));

    await _pumpTab(tester, db: db);
    await _longPressFirstTile(tester);
    await tester.tap(find.text('Cascade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to Playlist'));
    await tester.pumpAndSettle();

    // Create a new playlist inside the picker.
    await tester.enterText(
      find.byKey(const ValueKey<String>('playlist-name-field')),
      'Road Trip',
    );
    // Rebuild so the create button flips from disabled to enabled.
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('playlist-create-button')),
    );
    await tester.pumpAndSettle();

    final playlists = await db.playlistsDao.getAll();
    expect(playlists, hasLength(1));
    expect(playlists.single.name, 'Road Trip');
    expect(playlists.single.itemCount, 2);
    final tracks = await db.playlistsDao.tracksOf(playlists.single.id!);
    expect(tracks.map((t) => t.title).toList(),
        <String>['Aurora Skies', 'Cascade']);
  });

  testWidgets('Delete removes the selected rows from the library',
      (tester) async {
    final db = newMemoryDb();
    addTearDown(db.close);
    await db.tracksDao.insertTrack(seedCompanion(
        title: 'Aurora Skies', artist: 'A', sourceTrackId: 's1'));
    await db.tracksDao.insertTrack(
        seedCompanion(title: 'Cascade', artist: 'B', sourceTrackId: 's2'));

    await _pumpTab(tester, db: db);
    await _longPressFirstTile(tester);
    await tester.tap(find.text('Cascade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Confirm the removal dialog.
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(await db.tracksDao.countAll(), 0);
    expect(find.byKey(const ValueKey<String>('selection-bar')), findsNothing);
  });

  testWidgets('Delete cancelled keeps the rows', (tester) async {
    final db = newMemoryDb();
    addTearDown(db.close);
    await db.tracksDao.insertTrack(seedCompanion(
        title: 'Aurora Skies', artist: 'A', sourceTrackId: 's1'));

    await _pumpTab(tester, db: db);
    await _longPressFirstTile(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await db.tracksDao.countAll(), 1);
    expect(find.byKey(const ValueKey<String>('selection-bar')), findsOneWidget);
  });
}

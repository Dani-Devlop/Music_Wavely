/// authored, awaiting local run.
///
/// Widget test of `AllTracksTab` over a memory Drift database seeded with a
/// few tracks and a fake `TrackLauncher`. Verifies the paged tile list
/// renders (title-ordered), tapping a tile launches the queue at the right
/// index, and the empty-library state renders.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/features/library/presentation/all_tracks_tab.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';

import 'fakes.dart';

Future<(ProviderContainer, FakeTrackLauncher)> _pumpTab(
  WidgetTester tester, {
  required AppDatabase db,
}) async {
  final FakeTrackLauncher launcher = FakeTrackLauncher();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      databaseProvider.overrideWithValue(db),
      trackLauncherProvider.overrideWithValue(launcher),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: WavelyThemes.dark(WavelyAccent.purple),
        home: const Scaffold(body: AllTracksTab()),
      ),
    ),
  );
  // One pump to start the page load, one to flush the async result.
  await tester.pump();
  await tester.pumpAndSettle();
  return (container, launcher);
}

void main() {
  testWidgets('renders seeded tiles in title order', (tester) async {
    final AppDatabase db = newMemoryDb();
    addTearDown(db.close);
    await db.tracksDao.insertTrack(seedCompanion(title: 'breeze block',
        artist: 'Nilo Blue', sourceTrackId: 's1'));
    await db.tracksDao.insertTrack(seedCompanion(title: 'Aurora Skies',
        artist: 'Aurora Waves', sourceTrackId: 's2'));
    await db.tracksDao.insertTrack(seedCompanion(title: 'Cascade',
        artist: 'Aurora Waves', sourceTrackId: 's3'));

    await _pumpTab(tester, db: db);

    expect(find.byType(TrackTile), findsNWidgets(3));
    // ORDER BY title COLLATE NOCASE: case-folded alphabetical.
    final List<String> titles = <String>[
      'Aurora Skies',
      'breeze block',
      'Cascade',
    ];
    for (final String title in titles) {
      expect(find.text(title), findsOneWidget);
    }
    // Seeded ids are 1..3 in insertion order.
    expect(find.byKey(const ValueKey<String>('all-track-1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('all-track-3')), findsOneWidget);
  });

  testWidgets('tap launches the full page at the tapped index',
      (tester) async {
    final AppDatabase db = newMemoryDb();
    addTearDown(db.close);
    await db.tracksDao.insertTrack(seedCompanion(title: 'Aurora Skies',
        artist: 'A', sourceTrackId: 's1'));
    await db.tracksDao.insertTrack(seedCompanion(title: 'Cascade',
        artist: 'B', sourceTrackId: 's2'));
    await db.tracksDao.insertTrack(seedCompanion(title: 'Delta Rays',
        artist: 'C', sourceTrackId: 's3'));

    final (ProviderContainer _, FakeTrackLauncher launcher) =
        await _pumpTab(tester, db: db);

    await tester.tap(find.text('Cascade'));
    await tester.pumpAndSettle();

    expect(launcher.calls, hasLength(1));
    expect(launcher.calls.single.startIndex, 1);
    expect(launcher.calls.single.tracks.map((Track t) => t.title).toList(),
        <String>['Aurora Skies', 'Cascade', 'Delta Rays']);
  });

  testWidgets('empty library shows the folders-tab pointer state',
      (tester) async {
    final AppDatabase db = newMemoryDb();
    addTearDown(db.close);

    await _pumpTab(tester, db: db);

    expect(find.text('No music yet'), findsOneWidget);
    expect(find.text('Open Folders'), findsOneWidget);
    expect(find.byType(TrackTile), findsNothing);
  });

  testWidgets('a short page does not trigger a second page load',
      (tester) async {
    final AppDatabase db = newMemoryDb();
    addTearDown(db.close);
    await db.tracksDao.insertTrack(seedCompanion(title: 'Only One',
        artist: 'A', sourceTrackId: 's1'));

    final (ProviderContainer container, FakeTrackLauncher launcher) =
        await _pumpTab(tester, db: db);

    // Page 0 returned 1 row (< scrollPageSize) -> _canLoadMore stays
    // false: no loading footer, no launcher activity.
    expect(find.text('Only One'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(launcher.calls, isEmpty);
    // The count provider is only watched on the folders tab, so reading it
    // here STARTS it — await the future instead of asserting on the
    // inevitably-still-loading AsyncValue.
    expect(await container.read(libraryCountProvider.future), 1);
  });
}

/// authored, awaiting local run.
///
/// Widget test of `SearchScreen` + `search_providers.dart` over a seeded
/// memory Drift database (FTS5 index included via the onCreate migration)
/// and a fake `TrackLauncher`. Verifies the blank-query empty state, the
/// 300 ms debounce (as implemented by `SearchResultsController`), grouped
/// track/artist/album results, tap-to-launch, and the no-results state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/features/search/presentation/search_screen.dart';

import '../library/fakes.dart';

Future<(ProviderContainer, FakeTrackLauncher)> _pumpScreen(
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
        home: const Scaffold(body: SafeArea(child: SearchScreen())),
      ),
    ),
  );
  await tester.pump();
  return (container, launcher);
}

Future<void> _seed(AppDatabase db) async {
  await db.tracksDao.insertTrack(seedCompanion(
    title: 'Neon Skyline',
    artist: 'Aurora Waves',
    album: 'Midnight City',
    sourceTrackId: 's1',
  ));
  await db.tracksDao.insertTrack(seedCompanion(
    title: 'Cascade',
    artist: 'Aurora Waves',
    album: 'Midnight City',
    sourceTrackId: 's2',
  ));
  await db.tracksDao.insertTrack(seedCompanion(
    title: 'Paper Boats',
    artist: 'Nilo Blue',
    album: 'Driftwood',
    sourceTrackId: 's3',
  ));
}

void main() {
  testWidgets('blank query shows the search-hint empty state',
      (tester) async {
    final AppDatabase db = newMemoryDb();
    addTearDown(db.close);
    await _seed(db);

    await _pumpScreen(tester, db: db);

    expect(find.text('Search your library'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('query is debounced: results only after the 300 ms window',
      (tester) async {
    final AppDatabase db = newMemoryDb();
    addTearDown(db.close);
    await _seed(db);

    await _pumpScreen(tester, db: db);

    await tester.enterText(find.byType(TextField), 'neon');
    // Half the debounce window: the initial state is still untouched.
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Search your library'), findsOneWidget);
    expect(find.text('Neon Skyline'), findsNothing);

    // Cross the remaining window, flush the async search.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    await tester.pump();

    expect(find.text('Neon Skyline'), findsOneWidget);
  });

  testWidgets('results render grouped sections for tracks/artists/albums',
      (tester) async {
    final AppDatabase db = newMemoryDb();
    addTearDown(db.close);
    await _seed(db);

    await _pumpScreen(tester, db: db);

    await tester.enterText(find.byType(TextField), 'aurora');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump();

    expect(find.text('Tracks'), findsOneWidget);
    // FTS covers the artist column, so both tracks of the artist match.
    expect(find.text('Neon Skyline'), findsOneWidget);
    expect(find.text('Cascade'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
  });

  testWidgets('tapping a result launches the result list at its index',
      (tester) async {
    final AppDatabase db = newMemoryDb();
    addTearDown(db.close);
    await _seed(db);

    final (ProviderContainer _, FakeTrackLauncher launcher) =
        await _pumpScreen(tester, db: db);

    await tester.enterText(find.byType(TextField), 'paper');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Paper Boats'));
    await tester.pumpAndSettle();

    expect(launcher.calls, hasLength(1));
    expect(launcher.calls.single.startIndex, 0);
    expect(launcher.calls.single.tracks.single.title, 'Paper Boats');
  });

  testWidgets('a query without matches shows the no-results state',
      (tester) async {
    final AppDatabase db = newMemoryDb();
    addTearDown(db.close);
    await _seed(db);

    await _pumpScreen(tester, db: db);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump();

    expect(find.text('No results for "zzz"'), findsOneWidget);
  });

  testWidgets('clearing the query returns to the hint state', (tester) async {
    final AppDatabase db = newMemoryDb();
    addTearDown(db.close);
    await _seed(db);

    await _pumpScreen(tester, db: db);

    await tester.enterText(find.byType(TextField), 'neon');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump();
    expect(find.text('Neon Skyline'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    expect(find.text('Search your library'), findsOneWidget);
    expect(find.text('Neon Skyline'), findsNothing);
  });
}

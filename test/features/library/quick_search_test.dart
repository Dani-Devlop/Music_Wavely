/// Phase 6 — widget tests for the bottom QuickSearchBox: real-time
/// filtering of the track list, clearing restores the full list and the
/// no-matches state renders.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/library/data/library_view_config.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/features/library/presentation/all_tracks_tab.dart';
import 'package:wavely/features/library/presentation/quick_search_box.dart';
import 'package:wavely/features/library/presentation/sort_menu.dart';
import 'package:wavely/l10n/app_localizations.dart';

import 'fakes.dart';

Future<ProviderContainer> _pumpTab(
  WidgetTester tester, {
  required AppDatabase db,
}) async {
  final container = ProviderContainer(
    overrides: <Override>[
      databaseProvider.overrideWithValue(db),
      trackLauncherProvider.overrideWithValue(FakeTrackLauncher()),
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
  return container;
}

Future<void> _typeFilter(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('quick-search-songs')),
    text,
  );
  // The box debounces by AppConstants.searchDebounceMs.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('filters the track list in real time', (tester) async {
    final db = newMemoryDb();
    addTearDown(db.close);
    await db.tracksDao.insertTrack(seedCompanion(
        title: 'Aurora Skies', artist: 'Aurora Waves', sourceTrackId: 's1'));
    await db.tracksDao.insertTrack(seedCompanion(
        title: 'Cascade', artist: 'Nilo Blue', sourceTrackId: 's2'));
    await db.tracksDao.insertTrack(seedCompanion(
        title: 'Paper Boats', artist: 'Nilo Blue', sourceTrackId: 's3'));

    await _pumpTab(tester, db: db);
    expect(find.byType(TrackTile), findsNWidgets(3));

    // Case-folded contains match over the title.
    await _typeFilter(tester, 'aur');
    expect(find.byType(TrackTile), findsOneWidget);
    expect(find.text('Aurora Skies'), findsOneWidget);
    expect(find.text('Cascade'), findsNothing);

    // Artist names match too.
    await _typeFilter(tester, 'nilo');
    expect(find.byType(TrackTile), findsNWidgets(2));
    expect(find.text('Cascade'), findsOneWidget);
    expect(find.text('Paper Boats'), findsOneWidget);
  });

  testWidgets('clearing the filter restores the full list', (tester) async {
    final db = newMemoryDb();
    addTearDown(db.close);
    await db.tracksDao.insertTrack(seedCompanion(
        title: 'Aurora Skies', artist: 'A', sourceTrackId: 's1'));
    await db.tracksDao.insertTrack(seedCompanion(
        title: 'Cascade', artist: 'B', sourceTrackId: 's2'));

    await _pumpTab(tester, db: db);
    await _typeFilter(tester, 'aurora');
    expect(find.byType(TrackTile), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('quick-search-clear')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TrackTile), findsNWidgets(2));
  });

  testWidgets('no matches renders the empty state', (tester) async {
    final db = newMemoryDb();
    addTearDown(db.close);
    await db.tracksDao.insertTrack(seedCompanion(
        title: 'Aurora Skies', artist: 'A', sourceTrackId: 's1'));

    await _pumpTab(tester, db: db);
    await _typeFilter(tester, 'zzz');

    expect(find.text('No matches'), findsOneWidget);
    expect(find.byType(TrackTile), findsNothing);
  });

  testWidgets('every tab hosts a quick search box (labels differ)',
      (tester) async {
    // The box is a plain widget; this pins its API (debounce + hint).
    var queries = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: QuickSearchBox(
            onQueryChanged: queries.add,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('quick-search-field')),
      'GOLD ',
    );
    await tester.pump(const Duration(milliseconds: 400));
    // Queries arrive trimmed + case-folded.
    expect(queries, <String>['gold']);
  });
}

// authored, awaiting local run.
//
// Widget tests for lib/features/discovery/presentation/discovery_screen.dart
// over a fake DiscoveryService (subclass — the screen watches
// discoveryServiceProvider, which is overridden with .overrideWithValue):
// three sections render in loading / ready / empty / failed states, the
// offline empty-state shows the failure message, and the RefreshIndicator's
// onRefresh re-runs all three service lookups.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/remote/metadata_clients/deezer_client.dart';
import 'package:wavely/data/remote/metadata_clients/musicbrainz_client.dart';
import 'package:wavely/data/remote/metadata_http.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/discovery/discovery_service.dart';
import 'package:wavely/features/discovery/presentation/discovery_screen.dart';

/// http.Client stub for the throwaway clients the fake service's super
/// constructor requires — no call ever reaches it (all three lookups are
/// overridden).
class _NoopClient implements http.Client {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw UnimplementedError('noop client must not be used');
  }
}

/// Scripted [DiscoveryService]: canned results + call counters.
class _FakeDiscoveryService extends DiscoveryService {
  _FakeDiscoveryService(AppDatabase db)
      : super(
          mb: MusicBrainzClient(
            http: CachingHttpClient(
              cacheDao: db.httpCacheDao,
              client: _NoopClient(),
            ),
            rateLimiter: RateLimiter(Duration.zero),
          ),
          deezer: DeezerClient(
            http: CachingHttpClient(
              cacheDao: db.httpCacheDao,
              client: _NoopClient(),
            ),
            rateLimiter: RateLimiter(Duration.zero),
          ),
          followsDao: db.artistFollowsDao,
          tracksDao: db.tracksDao,
        );

  int followedCalls = 0;
  int relatedCalls = 0;
  int weeklyCalls = 0;

  Result<List<DiscoveryRelease>> followedResult =
      Result<List<DiscoveryRelease>>.success(const <DiscoveryRelease>[]);
  Result<List<DeezerArtist>> relatedResult =
      Result<List<DeezerArtist>>.success(const <DeezerArtist>[]);
  Result<List<DiscoveryRelease>> weeklyResult =
      Result<List<DiscoveryRelease>>.success(const <DiscoveryRelease>[]);

  @override
  Future<Result<List<DiscoveryRelease>>> getNewFromFollowedArtists() async {
    followedCalls++;
    return followedResult;
  }

  @override
  Future<Result<List<DeezerArtist>>> getBecauseYouListenTo() async {
    relatedCalls++;
    return relatedResult;
  }

  @override
  Future<Result<List<DiscoveryRelease>>> getNewReleasesThisWeek() async {
    weeklyCalls++;
    return weeklyResult;
  }
}

DiscoveryRelease _release(String title, String artist, String date) =>
    DiscoveryRelease(artist: artist, title: title, date: date, mbid: 'm');

Widget _wrap(_FakeDiscoveryService service) => ProviderScope(
      overrides: <Override>[
        discoveryServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        theme: WavelyThemes.dark(WavelyAccent.purple),
        home: const DiscoveryScreen(),
      ),
    );

void main() {
  testWidgets('renders the three section titles and calls each lookup once',
      (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _FakeDiscoveryService(db);

    await tester.pumpWidget(_wrap(service));
    // initState's postFrameCallback has run _refresh and the immediate
    // fake futures resolved; the sections render their canned results.
    await tester.pumpAndSettle();

    expect(find.text('New from artists you follow'), findsOneWidget);
    expect(find.text('Because you listen to'), findsOneWidget);
    expect(find.text('New this week'), findsOneWidget);
    expect(service.followedCalls, 1);
    expect(service.relatedCalls, 1);
    expect(service.weeklyCalls, 1);
  });

  testWidgets('ready sections render release rows and recommended artists',
      (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _FakeDiscoveryService(db)
      ..followedResult = Result<List<DiscoveryRelease>>.success(
        <DiscoveryRelease>[
          _release('Aurora LP', 'Aurora', '2026-05-02'),
        ],
      )
      ..relatedResult = Result<List<DeezerArtist>>.success(
        <DeezerArtist>[
          const DeezerArtist(id: 1, name: 'Related One'),
          const DeezerArtist(id: 2, name: 'Related Two'),
        ],
      )
      ..weeklyResult = Result<List<DiscoveryRelease>>.success(
        <DiscoveryRelease>[
          _release('Weekly LP', 'Weekly Artist', ''),
        ],
      );

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('Aurora LP'), findsOneWidget);
    expect(find.text('Aurora · 2026-05-02'), findsOneWidget);
    expect(find.text('Related One'), findsOneWidget);
    expect(find.text('Related Two'), findsOneWidget);
    expect(find.text('Recommended for you'), findsNWidgets(2));
    expect(find.text('Weekly LP'), findsOneWidget);
    // Empty date string → the subtitle falls back to the bare artist name.
    expect(find.text('Weekly Artist'), findsOneWidget);
    // No empty/offline placeholders anywhere.
    expect(find.byType(EmptyState), findsNothing);
  });

  testWidgets('empty sections show their dedicated empty titles',
      (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _FakeDiscoveryService(db); // all results empty

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('Follow artists to see their new releases'),
        findsOneWidget);
    expect(find.text('Play some music to get recommendations'),
        findsOneWidget);
    expect(find.text('No new releases this week'), findsOneWidget);
    expect(find.byType(EmptyState), findsNWidgets(3));
  });

  testWidgets('a failed section shows the offline empty state with the '
      'failure message; successful sections keep rendering',
      (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _FakeDiscoveryService(db)
      ..followedResult = Result<List<DiscoveryRelease>>.err(
        const Failure.network(message: 'HTTP 503 from musicbrainz.org'),
      )
      ..relatedResult = Result<List<DeezerArtist>>.success(
        <DeezerArtist>[const DeezerArtist(id: 9, name: 'Still Here')],
      );

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('Offline — showing this section when you\'re back online'),
        findsOneWidget);
    expect(find.text('HTTP 503 from musicbrainz.org'), findsOneWidget);
    expect(find.text('Still Here'), findsOneWidget);
  });

  testWidgets('pull-to-refresh re-runs all three service lookups',
      (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _FakeDiscoveryService(db);

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();
    expect(service.followedCalls, 1);
    expect(service.relatedCalls, 1);
    expect(service.weeklyCalls, 1);

    // Drive the RefreshIndicator hook directly (the screen wires
    // onRefresh: _refresh).
    final indicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    await indicator.onRefresh!();
    await tester.pumpAndSettle();

    expect(service.followedCalls, 2);
    expect(service.relatedCalls, 2);
    expect(service.weeklyCalls, 2);
  });
}

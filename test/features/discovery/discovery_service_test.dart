// authored, awaiting local run.
//
// Contract tests for lib/features/discovery/discovery_service.dart over a
// memory drift database + fake HTTP (routing MockClient → canned MusicBrainz
// / Deezer JSON):
// - getNewFromFollowedArtists: period filter (followedAt − 30d), MBID
//   resolution for mbid-less follows (not persisted), per-follow failure
//   skip, newest-first sorting, 6h cache reuse (2nd call → no HTTP).
// - getBecauseYouListenTo: top-3 artist seeding from play history, Deezer
//   search → related chain, name dedupe + seed/follow exclusion, partial
//   failure degradation, total failure, empty history.
// - getNewReleasesThisWeek: 7-day window, seed budget of 3 with case-folded
//   dedupe, all-fail error mapping.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/remote/metadata_clients/deezer_client.dart';
import 'package:wavely/data/remote/metadata_clients/musicbrainz_client.dart';
import 'package:wavely/data/remote/metadata_http.dart';
import 'package:wavely/features/discovery/discovery_service.dart';

Success<T> _ok<T>(Result<T> result) => result as Success<T>;
Err<T> _err<T>(Result<T> result) => result as Err<T>;

AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

/// Canned routing for the discovery HTTP stack.
class _CannedRemote {
  final Map<String, String> mbSearch = <String, String>{};
  final Map<String, String> mbGroups = <String, String>{};
  final Map<String, String> deezerSearch = <String, String>{};
  final Map<String, String> deezerRelated = <String, String>{};
  bool mbSearchFails = false;
  bool mbGroupsFails = false;
  bool deezerSearchFails = false;

  final List<Uri> log = <Uri>[];

  http.Client buildClient() => MockClient((request) async {
        final url = request.url;
        log.add(url);
        switch (url.host) {
          case 'musicbrainz.org':
            if (url.path.endsWith('/artist')) {
              if (mbSearchFails) {
                return http.Response('mb down', 500);
              }
              final body = mbSearch[url.queryParameters['query']];
              return http.Response(body ?? '{"artists":[]}', 200);
            }
            if (url.path.endsWith('/release-group')) {
              if (mbGroupsFails) {
                return http.Response('mb down', 500);
              }
              final body = mbGroups[url.queryParameters['artist']];
              return http.Response(body ?? '{"release-groups":[]}', 200);
            }
            break;
          case 'api.deezer.com':
            if (url.path == '/search/artist') {
              if (deezerSearchFails) {
                return http.Response('deezer down', 500);
              }
              final body = deezerSearch[url.queryParameters['q']] ??
                  '{"data":[]}';
              return http.Response(body, 200);
            }
            if (url.path.endsWith('/related')) {
              final segments = url.pathSegments;
              final id = segments[segments.length - 2];
              final body = deezerRelated[id] ?? '{"data":[]}';
              return http.Response(body, 200);
            }
            break;
        }
        return http.Response('unexpected ${url.host}${url.path}', 404);
      });
}

({DiscoveryService service, List<Uri> log}) _build(
  AppDatabase db,
  _CannedRemote remote, {
  DateTime Function()? now,
}) {
  final cachingHttp = CachingHttpClient(
    cacheDao: db.httpCacheDao,
    client: remote.buildClient(),
  );
  final service = DiscoveryService(
    mb: MusicBrainzClient(
        http: cachingHttp, rateLimiter: RateLimiter(Duration.zero)),
    deezer: DeezerClient(
        http: cachingHttp, rateLimiter: RateLimiter(Duration.zero)),
    followsDao: db.artistFollowsDao,
    tracksDao: db.tracksDao,
    playsDao: db.playsDao,
    now: now,
  );
  return (service: service, log: remote.log);
}

Future<Track> _seedTrack(
  AppDatabase db, {
  required String sourceTrackId,
  required String title,
  required String artist,
  int playCount = 0,
  String? genre,
}) {
  return db.tracksDao.upsertBySource(
    TracksCompanion.insert(
      sourceId: 'local',
      sourceTrackId: sourceTrackId,
      title: title,
      artist: artist,
      durationMs: 1000,
      format: 'mp3',
      addedAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      genre: Value(genre),
      playCount: Value(playCount),
    ),
  );
}

Future<void> _seedPlay(AppDatabase db, int trackId, DateTime at) {
  return db.playsDao.insertPlay(
    PlaysCompanion.insert(
      trackId: trackId,
      startedAt: at,
      listenedMs: 1000,
      source: 'local',
      deviceId: 'device',
    ),
  );
}

/// Direct insert so [followedAt] is deterministic (the dao pins
/// DateTime.now()).
Future<void> _seedFollow(
  AppDatabase db,
  String artistName, {
  String? mbid,
  required DateTime followedAt,
}) {
  return db.into(db.artistFollows).insert(
        ArtistFollowsCompanion.insert(
          artistName: artistName,
          mbid: Value(mbid),
          followedAt: followedAt,
        ),
      );
}

void main() {
  group('getNewFromFollowedArtists', () {
    test('no follows → empty success, no HTTP', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final remote = _CannedRemote();
      final (service: service, log: log) = _build(db, remote);

      final result = await service.getNewFromFollowedArtists();

      expect(_ok(result).value, isEmpty);
      expect(log, isEmpty);
    });

    test('releases of a stored-MBID follow are mapped with the local '
        'artist name', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final remote = _CannedRemote()
        ..mbGroups['mbid-f'] =
            '{"release-groups":[{"id":"g-1","title":"Followed LP",'
            '"first-release-date":"2026-06-01","primary-type":"Album"}]}';
      await _seedFollow(
        db,
        'Followed Artist',
        mbid: 'mbid-f',
        followedAt: DateTime(2026, 6, 15),
      );
      final (service: service, log: log) = _build(db, remote);

      final result = await service.getNewFromFollowedArtists();

      final releases = _ok(result).value;
      expect(releases, hasLength(1));
      expect(releases.single.artist, 'Followed Artist');
      expect(releases.single.title, 'Followed LP');
      expect(releases.single.date, '2026-06-01');
      expect(releases.single.mbid, 'mbid-f');
      expect(releases.single.dateValue, DateTime(2026, 6, 1));
      // The stored MBID short-circuits the search — only the group lookup
      // is requested.
      expect(log, hasLength(1));
      expect(log.single.queryParameters['artist'], 'mbid-f');
    });

    test('period filter: only groups at/after followedAt − 30 days survive',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final remote = _CannedRemote()
        ..mbGroups['mbid-f'] =
            '{"release-groups":['
            '{"id":"g-old","title":"Too old",'
            '"first-release-date":"2026-05-15"},'
            '{"id":"g-edge","title":"Exactly at cutoff",'
            '"first-release-date":"2026-05-16"},'
            '{"id":"g-new","title":"Recent",'
            '"first-release-date":"2026-06-14"}]}';
      await _seedFollow(
        db,
        'Followed Artist',
        mbid: 'mbid-f',
        followedAt: DateTime(2026, 6, 15),
      );
      final (service: service, _) = _build(db, remote);

      final releases = _ok(await service.getNewFromFollowedArtists()).value;

      // Cutoff string is '2026-05-16': one day before it is dropped.
      expect(
        [for (final release in releases) release.mbid],
        everyElement('mbid-f'),
      );
      expect(
        [for (final release in releases) release.title],
        <String>['Recent', 'Exactly at cutoff'],
      );
    });

    test('mbid-less follows resolve through the MB search (resolution is '
        'NOT persisted back to the dao)', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final remote = _CannedRemote()
        ..mbSearch['Raw Artist'] =
            '{"artists":[{"id":"mbid-resolved","name":"Raw Artist"}]}'
        ..mbGroups['mbid-resolved'] =
            '{"release-groups":[{"id":"g-2","title":"Resolved LP",'
            '"first-release-date":"2026-06-10","primary-type":"Album"}]}';
      await _seedFollow(
        db,
        'Raw Artist',
        followedAt: DateTime(2026, 6, 15),
      );
      final (service: service, log: log) = _build(db, remote);

      final releases = _ok(await service.getNewFromFollowedArtists()).value;

      expect(releases.single.title, 'Resolved LP');
      expect(releases.single.mbid, 'mbid-resolved');
      // search → release-groups, in that order.
      expect(log, hasLength(2));
      expect(log.first.path, '/ws/2/artist');
      expect(log.last.path, '/ws/2/release-group');
      expect(log.last.queryParameters['artist'], 'mbid-resolved');

      final rows = await db.artistFollowsDao.all();
      expect(rows.single.mbid, isNull);
    });

    test('all lookups failing degrades to an empty success (no throw)',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final remote = _CannedRemote()..mbGroupsFails = true;
      await _seedFollow(
        db,
        'Broken Artist One',
        mbid: 'mbid-broken-1',
        followedAt: DateTime(2026, 6, 15),
      );
      await _seedFollow(
        db,
        'Broken Artist Two',
        mbid: 'mbid-broken-2',
        followedAt: DateTime(2026, 6, 15),
      );
      final (service: service, _) = _build(db, remote);

      final result = await service.getNewFromFollowedArtists();

      // Every follow's lookup failed → nothing contributes; the method
      // still resolves to a success with no releases.
      expect(result.isSuccess, isTrue);
      expect(_ok(result).value, isEmpty);
    });

    test('mixed failure: one broken lookup does not lose the good one',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final remote = _CannedRemote()
        ..mbGroups['mbid-broken'] = 'not json at all'
        ..mbGroups['mbid-ok'] =
            '{"release-groups":[{"id":"g-3","title":"Survivor",'
            '"first-release-date":"2026-06-09","primary-type":"Album"}]}';
      await _seedFollow(
        db,
        'Broken Artist',
        mbid: 'mbid-broken',
        followedAt: DateTime(2026, 6, 15),
      );
      await _seedFollow(
        db,
        'Ok Artist',
        mbid: 'mbid-ok',
        followedAt: DateTime(2026, 6, 15),
      );
      final (service: service, _) = _build(db, remote);

      final releases = _ok(await service.getNewFromFollowedArtists()).value;

      expect(releases, hasLength(1));
      expect(releases.single.artist, 'Ok Artist');
      expect(releases.single.title, 'Survivor');
    });

    test('results are sorted newest-first', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final remote = _CannedRemote()
        ..mbGroups['mbid-f'] =
            '{"release-groups":['
            '{"id":"g-1","title":"Older",'
            '"first-release-date":"2026-06-01"},'
            '{"id":"g-2","title":"Newest",'
            '"first-release-date":"2026-06-12"},'
            '{"id":"g-3","title":"Middle",'
            '"first-release-date":"2026-06-08"}]}';
      await _seedFollow(
        db,
        'Followed Artist',
        mbid: 'mbid-f',
        followedAt: DateTime(2026, 6, 15),
      );
      final (service: service, _) = _build(db, remote);

      final releases = _ok(await service.getNewFromFollowedArtists()).value;

      expect(
        [for (final release in releases) release.title],
        <String>['Newest', 'Middle', 'Older'],
      );
    });

    test('6h cache reuse: the second run performs no HTTP', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final remote = _CannedRemote()
        ..mbGroups['mbid-c'] =
            '{"release-groups":[{"id":"g-9","title":"Cached LP",'
            '"first-release-date":"2026-06-05","primary-type":"Album"}]}';
      await _seedFollow(
        db,
        'Cached Artist',
        mbid: 'mbid-c',
        followedAt: DateTime(2026, 6, 15),
      );
      final (service: service, log: log) = _build(db, remote);

      final first = _ok(await service.getNewFromFollowedArtists()).value;
      final second = _ok(await service.getNewFromFollowedArtists()).value;

      expect(first.single.title, 'Cached LP');
      expect(second.single.title, 'Cached LP');
      expect(log, hasLength(1)); // served from the http_cache on run 2
    });
  });

  group('getBecauseYouListenTo', () {
    test('seeds the top 3 artists from play history, dedupes related '
        'artists and excludes seeds + followed', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final tAlpha1 = await _seedTrack(db,
          sourceTrackId: 'a1', title: 'A1', artist: 'Alpha');
      final tAlpha2 = await _seedTrack(db,
          sourceTrackId: 'a2', title: 'A2', artist: 'Alpha');
      final tBeta =
          await _seedTrack(db, sourceTrackId: 'b1', title: 'B1', artist: 'Beta');
      final tGamma = await _seedTrack(db,
          sourceTrackId: 'c1', title: 'C1', artist: 'Gamma');
      final tDelta = await _seedTrack(db,
          sourceTrackId: 'd1', title: 'D1', artist: 'Delta');
      // Play weights: Alpha owns the 2 most-played tracks (top-3 artists
      // = Alpha, Beta, Gamma — Delta misses the budget), ties break
      // alphabetically.
      for (var i = 0; i < 10; i++) {
        await _seedPlay(db, tAlpha1.id!, DateTime(2026, 6, 1, 8, i));
      }
      for (var i = 0; i < 9; i++) {
        await _seedPlay(db, tAlpha2.id!, DateTime(2026, 6, 2, 8, i));
      }
      for (var i = 0; i < 8; i++) {
        await _seedPlay(db, tBeta.id!, DateTime(2026, 6, 3, 8, i));
      }
      for (var i = 0; i < 7; i++) {
        await _seedPlay(db, tGamma.id!, DateTime(2026, 6, 4, 8, i));
      }
      for (var i = 0; i < 6; i++) {
        await _seedPlay(db, tDelta.id!, DateTime(2026, 6, 5, 8, i));
      }
      await _seedFollow(
        db,
        'Followed One',
        mbid: 'mbid-f',
        followedAt: DateTime(2026, 6, 15),
      );

      final remote = _CannedRemote()
        ..deezerSearch['Alpha'] =
            '{"data":[{"id":101,"name":"Alpha","picture_medium":"p-alpha"}]}'
        ..deezerSearch['Beta'] = '{"data":[{"id":201,"name":"Beta"}]}'
        ..deezerSearch['Gamma'] = '{"data":[{"id":301,"name":"Gamma"}]}'
        ..deezerRelated['101'] = '{"data":['
            '{"id":101,"name":"Alpha"},' // seed itself → excluded
            '{"id":102,"name":"ALPHA live"},' // kept
            '{"id":103,"name":"beta"},' // seed name (case-folded) → excluded
            '{"id":104,"name":"New Artist X"}]}' // kept
        ..deezerRelated['201'] = '{"data":['
            '{"id":105,"name":"gamma"},' // seed → excluded
            '{"id":106,"name":"Followed One"},' // followed → excluded
            '{"id":107,"name":"New Artist Y"}]}' // kept
        ..deezerRelated['301'] = '{"data":['
            '{"id":102,"name":"ALPHA live"},' // duplicate → excluded
            '{"id":108,"name":"New Artist Z"}]}'; // kept
      final (service: service, log: log) = _build(db, remote);

      final result = await service.getBecauseYouListenTo();

      final artists = _ok(result).value;
      expect(
        [for (final artist in artists) artist.name],
        <String>['ALPHA live', 'New Artist X', 'New Artist Y', 'New Artist Z'],
      );
      expect(artists.first.id, 102);
      expect(artists.first.pictureUrl, 'p-alpha');
      // Deezer is hit exactly once per seed for search + once for related.
      expect(
        [for (final uri in log) uri.path]..sort(),
        <String>[
          '/artist/101/related',
          '/artist/201/related',
          '/artist/301/related',
          '/search/artist',
          '/search/artist',
          '/search/artist',
        ],
      );
    });

    test('a failing seed is skipped; the remaining seeds still contribute',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final tAlpha = await _seedTrack(db,
          sourceTrackId: 'a1', title: 'A1', artist: 'Alpha');
      final tBeta =
          await _seedTrack(db, sourceTrackId: 'b1', title: 'B1', artist: 'Beta');
      await _seedPlay(db, tAlpha.id!, DateTime(2026, 6, 1, 8));
      await _seedPlay(db, tBeta.id!, DateTime(2026, 6, 1, 9));

      final remote = _CannedRemote()
        ..deezerSearch['Alpha'] = '{"data":[]}' // no match → seed skipped
        ..deezerSearch['Beta'] = '{"data":[{"id":201,"name":"Beta"}]}'
        ..deezerRelated['201'] =
            '{"data":[{"id":202,"name":"Beta Related"}]}';
      final (service: service, _) = _build(db, remote);

      final artists = _ok(await service.getBecauseYouListenTo()).value;

      expect([for (final artist in artists) artist.name],
          <String>['Beta Related']);
    });

    test('every seed failing resolves to an error (last failure wins)',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final tAlpha = await _seedTrack(db,
          sourceTrackId: 'a1', title: 'A1', artist: 'Alpha');
      await _seedPlay(db, tAlpha.id!, DateTime(2026, 6, 1, 8));

      final remote = _CannedRemote()..deezerSearchFails = true;
      final (service: service, _) = _build(db, remote);

      final result = await service.getBecauseYouListenTo();

      expect(result.isErr, isTrue);
      expect(_err(result).failure, isA<NetworkFailure>());
    });

    test('no listening history and no library → empty success', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final remote = _CannedRemote();
      final (service: service, log: log) = _build(db, remote);

      final result = await service.getBecauseYouListenTo();

      expect(_ok(result).value, isEmpty);
      expect(log, isEmpty);
    });

    test('without a playsDao the seeds come from tracks.play_count',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      await _seedTrack(db,
          sourceTrackId: 'a1', title: 'A1', artist: 'Alpha', playCount: 5);
      await _seedTrack(db,
          sourceTrackId: 'b1', title: 'B1', artist: 'Beta', playCount: 2);

      final remote = _CannedRemote()
        ..deezerSearch['Alpha'] = '{"data":[{"id":101,"name":"Alpha"}]}'
        ..deezerSearch['Beta'] = '{"data":[{"id":201,"name":"Beta"}]}'
        ..deezerRelated['101'] = '{"data":[{"id":102,"name":"Alpha Related"}]}'
        ..deezerRelated['201'] = '{"data":[{"id":202,"name":"Beta Related"}]}';

      final http = CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: remote.buildClient(),
      );
      final service = DiscoveryService(
        mb: MusicBrainzClient(
            http: http, rateLimiter: RateLimiter(Duration.zero)),
        deezer:
            DeezerClient(http: http, rateLimiter: RateLimiter(Duration.zero)),
        followsDao: db.artistFollowsDao,
        tracksDao: db.tracksDao,
        // playsDao deliberately omitted → play_count path.
      );

      final artists = _ok(await service.getBecauseYouListenTo()).value;

      // Alpha (weight 5) is ranked before Beta (weight 2).
      expect(
        [for (final artist in artists) artist.name],
        <String>['Alpha Related', 'Beta Related'],
      );
      expect(
        [
          for (final uri
              in remote.log.where((uri) => uri.path == '/search/artist'))
            uri.queryParameters['q'],
        ],
        <String>['Alpha', 'Beta'],
      );
    });
  });

  group('getNewReleasesThisWeek', () {
    test('seeds followed + most-played artists (max 3, case-folded dedupe) '
        'and keeps only releases inside the last 7 days', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final fixedNow = DateTime(2026, 6, 15, 12);
      final tPlayed = await _seedTrack(db,
          sourceTrackId: 'p1', title: 'P1', artist: 'Played Artist');
      await _seedPlay(
          db, tPlayed.id!, fixedNow.subtract(const Duration(days: 1)));
      // A second played artist with the same name in different case must
      // collapse into one seed.
      final tPlayed2 = await _seedTrack(db,
          sourceTrackId: 'p2', title: 'P2', artist: 'PLAYED ARTIST');
      await _seedPlay(
          db, tPlayed2.id!, fixedNow.subtract(const Duration(days: 2)));
      await _seedFollow(
        db,
        'Followed Artist',
        mbid: 'mbid-f',
        followedAt: fixedNow,
      );

      final remote = _CannedRemote()
        ..mbSearch['Played Artist'] =
            '{"artists":[{"id":"mbid-p","name":"Played Artist"}]}'
        ..mbGroups['mbid-f'] = '{"release-groups":['
            '{"id":"g-1","title":"In window","first-release-date":"2026-06-14"},'
            '{"id":"g-2","title":"Outside","first-release-date":"2026-05-01"}]}'
        ..mbGroups['mbid-p'] = '{"release-groups":['
            '{"id":"g-3","title":"Played in window",'
            '"first-release-date":"2026-06-10"}]}';

      final cachingHttp = CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: remote.buildClient(),
      );
      final service = DiscoveryService(
        mb: MusicBrainzClient(
            http: cachingHttp, rateLimiter: RateLimiter(Duration.zero)),
        deezer: DeezerClient(
            http: cachingHttp, rateLimiter: RateLimiter(Duration.zero)),
        followsDao: db.artistFollowsDao,
        tracksDao: db.tracksDao,
        playsDao: db.playsDao,
        now: () => fixedNow,
      );

      final releases = _ok(await service.getNewReleasesThisWeek()).value;

      // The 7-day cutoff (client-side `since` filter) drops 2026-05-01.
      expect(
        [for (final release in releases) release.title],
        <String>['In window', 'Played in window'],
      );
      expect(releases.first.artist, 'Followed Artist');
      expect(releases.last.artist, 'Played Artist');
      expect(releases.last.mbid, 'mbid-p');
      // 'PLAYED ARTIST' collapsed into the 'Played Artist' seed → only ONE
      // search for it.
      final searches = remote.log
          .where((uri) => uri.path == '/ws/2/artist')
          .toList(growable: false);
      expect(searches, hasLength(1));
      expect(searches.single.queryParameters['query'], 'Played Artist');
    });

    test('a seed whose group lookup fails produces an error when no seed '
        'succeeds', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final fixedNow = DateTime(2026, 6, 15, 12);
      await _seedFollow(
        db,
        'Broken Artist',
        mbid: 'mbid-broken',
        followedAt: fixedNow,
      );
      final remote = _CannedRemote()..mbGroupsFails = true;

      final cachingHttp = CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: remote.buildClient(),
      );
      final service = DiscoveryService(
        mb: MusicBrainzClient(
            http: cachingHttp, rateLimiter: RateLimiter(Duration.zero)),
        deezer: DeezerClient(
            http: cachingHttp, rateLimiter: RateLimiter(Duration.zero)),
        followsDao: db.artistFollowsDao,
        tracksDao: db.tracksDao,
        now: () => fixedNow,
      );

      final result = await service.getNewReleasesThisWeek();

      expect(result.isErr, isTrue);
      expect(_err(result).failure, isA<NetworkFailure>());
    });

    test('no seeds at all → empty success', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final remote = _CannedRemote();
      final (service: service, log: log) = _build(db, remote);

      final result = await service.getNewReleasesThisWeek();

      expect(_ok(result).value, isEmpty);
      expect(log, isEmpty);
    });
  });
}

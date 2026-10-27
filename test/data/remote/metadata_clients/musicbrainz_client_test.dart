// authored, awaiting local run.
//
// Fixture-driven contract tests for lib/data/remote/metadata_clients/
// musicbrainz_client.dart: artist search parsing, release-group listing with
// the `since` cutoff, request-shape assertions (endpoints + query params),
// and error mapping (429/404 → network failure, malformed body → parsing
// failure, empty result → null success).
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/remote/metadata_clients/musicbrainz_client.dart';
import 'package:wavely/data/remote/metadata_http.dart';

AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

Success<T> _ok<T>(Result<T> result) => result as Success<T>;
Err<T> _err<T>(Result<T> result) => result as Err<T>;

const String _searchBody =
    '{"created":"2026-01-01T00:00:00","count":2,"offset":0,"artists":['
    '{"id":"mbid-1111","name":"Radiohead","score":100,'
    '"area":{"id":"area-1","name":"Oxford"}},'
    '{"id":"mbid-2222","name":"Radiohead tribute","score":42}]}';

const String _groupsBody =
    '{"release-group-count":3,"release-groups":['
    '{"id":"g-1","title":"Recent LP","first-release-date":"2026-05-20",'
    '"primary-type":"Album"},'
    '{"id":"g-2","title":"Older LP","first-release-date":"2026-05-16",'
    '"primary-type":"Album"},'
    '{"id":"g-3","title":"Undated EP","primary-type":"EP"}]}';

void main() {
  group('MusicBrainzClient.searchArtist', () {
    test('parses the first artist match incl. area', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final requests = <http.Request>[];
      final client = MusicBrainzClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(_searchBody, 200);
          }),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.searchArtist('Radiohead');

      final artist = _ok(result).value;
      expect(artist, isNotNull);
      expect(artist!.mbid, 'mbid-1111');
      expect(artist.name, 'Radiohead');
      expect(artist.area, 'Oxford');

      // Request shape per docs/METADATA_SOURCES.md.
      expect(requests.single.url.host, 'musicbrainz.org');
      expect(requests.single.url.path, '/ws/2/artist');
      expect(requests.single.url.queryParameters['query'], 'Radiohead');
      expect(requests.single.url.queryParameters['fmt'], 'json');
      expect(requests.single.url.queryParameters['limit'], '1');
      expect(requests.single.headers['user-agent'], MetadataHttp.userAgent);
    });

    test('empty artists list resolves to a null SUCCESS (no match)', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = MusicBrainzClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async =>
              http.Response('{"artists":[]}', 200)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.searchArtist('Nobody Known');

      expect(result.isSuccess, isTrue);
      expect(_ok(result).value, isNull);
    });

    test('artist entry without an id resolves to null, not failure',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = MusicBrainzClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async =>
              http.Response('{"artists":[{"name":"Ghost"}]}', 200)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.searchArtist('Ghost');

      expect(result.isSuccess, isTrue);
      expect(_ok(result).value, isNull);
    });

    test('HTTP 429 maps to Failure.network with the status in the message',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = MusicBrainzClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async =>
              http.Response('too many requests', 429)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.searchArtist('Radiohead');

      expect(result.isErr, isTrue);
      expect(_err(result).failure, isA<NetworkFailure>());
      expect(_err(result).failure.message, contains('429'));
    });

    test('HTTP 404 maps to Failure.network as well', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = MusicBrainzClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async => http.Response('nope', 404)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.searchArtist('Radiohead');

      expect(_err(result).failure, isA<NetworkFailure>());
      expect(_err(result).failure.message, contains('404'));
    });

    test('malformed JSON maps to Failure.parsing', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = MusicBrainzClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient(
              (request) async => http.Response('<html>bot page</html>', 200)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.searchArtist('Radiohead');

      expect(_err(result).failure, isA<ParsingFailure>());
      expect(_err(result).failure.message, contains('Malformed MusicBrainz'));
    });

    test('non-map payload maps to Failure.parsing', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = MusicBrainzClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async => http.Response('[1,2,3]', 200)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.searchArtist('Radiohead');

      expect(_err(result).failure, isA<ParsingFailure>());
      expect(_err(result).failure.message, contains('Unexpected MusicBrainz'));
    });
  });

  group('MusicBrainzClient.releaseGroups', () {
    test('parses groups and applies the since cutoff (date-string compare)',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final requests = <http.Request>[];
      final client = MusicBrainzClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(_groupsBody, 200);
          }),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.releaseGroups(
        'mbid-1111',
        since: DateTime(2026, 5, 17),
      );

      final groups = _ok(result).value;
      // 2026-05-16 is before the cutoff, the undated EP cannot be proven
      // "new" — both are dropped.
      expect(
        [for (final group in groups) group.id],
        <String>['g-1'],
      );
      expect(groups.single.title, 'Recent LP');
      expect(groups.single.firstReleaseDate, '2026-05-20');
      expect(groups.single.primaryType, 'Album');

      expect(requests.single.url.host, 'musicbrainz.org');
      expect(requests.single.url.path, '/ws/2/release-group');
      expect(requests.single.url.queryParameters['artist'], 'mbid-1111');
      expect(requests.single.url.queryParameters['type'], 'album');
      expect(requests.single.url.queryParameters['fmt'], 'json');
      expect(requests.single.url.queryParameters['sort'],
          'first-release-date desc');
    });

    test('without since every dated and undated group is kept', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = MusicBrainzClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async =>
              http.Response(_groupsBody, 200)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.releaseGroups('mbid-1111');

      expect(_ok(result).value, hasLength(3));
    });

    test('entries without id or title are skipped, missing primary-type '
        'becomes empty string', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      const body = '{"release-groups":['
          '{"title":"no id"},'
          '{"id":"g-9","title":"Minimal"}'
          ']}';
      final client = MusicBrainzClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async => http.Response(body, 200)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.releaseGroups('mbid-1');

      final groups = _ok(result).value;
      expect(groups, hasLength(1));
      expect(groups.single.id, 'g-9');
      expect(groups.single.primaryType, '');
    });

    test('missing release-groups node parses to an empty success', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = MusicBrainzClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async => http.Response('{}', 200)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.releaseGroups('mbid-1');

      expect(result.isSuccess, isTrue);
      expect(_ok(result).value, isEmpty);
    });

    test('malformed JSON maps to Failure.parsing', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = MusicBrainzClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient(
              (request) async => http.Response('{"release-groups":', 200)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.releaseGroups('mbid-1');

      expect(_err(result).failure, isA<ParsingFailure>());
      expect(_err(result).failure.message, contains('Malformed MusicBrainz'));
    });

    test('HTTP failure is surfaced as Failure.network', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = MusicBrainzClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async => http.Response('err', 500)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.releaseGroups('mbid-1');

      expect(_err(result).failure, isA<NetworkFailure>());
    });
  });
}

// authored, awaiting local run.
//
// Fixture-driven contract tests for lib/data/remote/metadata_clients/
// deezer_client.dart: artist search, related artists, album lookup, the
// HTTP-200 `error` envelope (the documented Access-Denied degradation path),
// and malformed/failed response mapping.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/remote/metadata_clients/deezer_client.dart';

AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

Success<T> _ok<T>(Result<T> result) => result as Success<T>;
Err<T> _err<T>(Result<T> result) => result as Err<T>;

const String _searchBody = '{"data":['
    '{"id":4050205,"name":"Daft Punk","picture_medium":'
    '"https://e-cdns-images.dzcdn.net/images/artist/medium.jpg"}]}';

const String _relatedBody = '{"data":['
    '{"id":11,"name":"Justice","picture_medium":"p1"},'
    '{"id":"not-a-number","name":"Broken"},'
    '{"name":"No id"},'
    '{"id":12,"name":"Cassius"}'
    ']}';

void main() {
  group('DeezerClient.searchArtist', () {
    test('parses the first match with picture url', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final requests = <http.Request>[];
      final client = DeezerClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(_searchBody, 200);
          }),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.searchArtist('Daft Punk');

      final artist = _ok(result).value;
      expect(artist, isNotNull);
      expect(artist!.id, 4050205);
      expect(artist.name, 'Daft Punk');
      expect(artist.pictureUrl, contains('medium.jpg'));

      expect(requests.single.url.host, 'api.deezer.com');
      expect(requests.single.url.path, '/search/artist');
      expect(requests.single.url.queryParameters['q'], 'Daft Punk');
      expect(requests.single.url.queryParameters['limit'], '1');
    });

    test('empty data list resolves to null success', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = DeezerClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient(
              (request) async => http.Response('{"data":[]}', 200)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.searchArtist('Nobody');

      expect(result.isSuccess, isTrue);
      expect(_ok(result).value, isNull);
    });

    test('HTTP-200 error envelope (Access-Denied style) maps to '
        'Failure.network with the API message', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      const body =
          '{"error":{"type":"OAuthException","message":"Access denied",'
          '"code":200,"results":[]}}';
      final client = DeezerClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async => http.Response(body, 200)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.searchArtist('Daft Punk');

      expect(result.isErr, isTrue);
      final failure = _err(result).failure;
      expect(failure, isA<NetworkFailure>());
      expect(failure.message, contains('Deezer API error'));
      expect(failure.message, contains('Access denied'));
    });

    test('malformed JSON maps to Failure.parsing', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = DeezerClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async => http.Response('{data', 200)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.searchArtist('x');

      expect(_err(result).failure, isA<ParsingFailure>());
      expect(_err(result).failure.message, contains('Malformed Deezer'));
    });

    test('HTTP failure is surfaced as Failure.network', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = DeezerClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async => http.Response('no', 503)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.searchArtist('x');

      expect(_err(result).failure, isA<NetworkFailure>());
    });
  });

  group('DeezerClient.relatedArtists', () {
    test('parses the list and skips malformed entries', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final requests = <http.Request>[];
      final client = DeezerClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(_relatedBody, 200);
          }),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.relatedArtists(4050205, limit: 10);

      final artists = _ok(result).value;
      expect(
        [for (final artist in artists) artist.id],
        <int>[11, 12],
      );
      expect(artists.first.name, 'Justice');
      expect(artists.first.pictureUrl, 'p1');

      expect(requests.single.url.path, '/artist/4050205/related');
      expect(requests.single.url.queryParameters['limit'], '10');
    });

    test('the Access-Denied degradation: error envelope surfaces as '
        'Failure.network (UI hides the section)', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      const body =
          '{"error":{"type":"Exception","message":"Quota limit exceeded",'
          '"code":4}}';
      final client = DeezerClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async => http.Response(body, 200)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.relatedArtists(4050205);

      expect(result.isErr, isTrue);
      expect(_err(result).failure.message, contains('Quota limit exceeded'));
    });

    test('non-map payload (bare list) parses to an empty success', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = DeezerClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async => http.Response('[1,2]', 200)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.relatedArtists(1);

      expect(result.isSuccess, isTrue);
      expect(_ok(result).value, isEmpty);
    });
  });

  group('DeezerClient.album', () {
    test('parses album metadata', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final requests = <http.Request>[];
      const body =
          '{"id":302127,"title":"Discovery","cover_medium":"cover.jpg",'
          '"release_date":"2001-03-07"}';
      final client = DeezerClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(body, 200);
          }),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.album(302127);

      final album = _ok(result).value;
      expect(album, isNotNull);
      expect(album!.id, 302127);
      expect(album.title, 'Discovery');
      expect(album.coverUrl, 'cover.jpg');
      expect(album.releaseDate, '2001-03-07');
      expect(requests.single.url.path, '/album/302127');
    });

    test('unknown album (error envelope) resolves to failure, not null',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      const body =
          '{"error":{"type":"DataException","message":"no data","code":800}}';
      final client = DeezerClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async => http.Response(body, 200)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.album(999999);

      expect(result.isErr, isTrue);
      expect(_err(result).failure, isA<NetworkFailure>());
    });

    test('album without id/title resolves to null success', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = DeezerClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client:
              MockClient((request) async => http.Response('{"title":"?"}', 200)),
        ),
        rateLimiter: RateLimiter(Duration.zero),
      );

      final result = await client.album(1);

      expect(result.isSuccess, isTrue);
      expect(_ok(result).value, isNull);
    });
  });
}

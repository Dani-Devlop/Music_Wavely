// authored, awaiting local run.
//
// Contract tests for lib/data/remote/metadata_clients/reddit_client.dart:
// valid listing parsing (permalink joining, created_utc conversion, skipping
// malformed children) and the documented HTML bot-page graceful degradation
// (non-JSON body → Failure.parsing('reddit blocked (non-JSON response)')).
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/remote/metadata_clients/reddit_client.dart';

AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

Success<T> _ok<T>(Result<T> result) => result as Success<T>;
Err<T> _err<T>(Result<T> result) => result as Err<T>;

// 1767225600 == 2026-01-01T00:00:00Z.
const String _listingBody =
    '{"kind":"Listing","data":{"children":['
    '{"kind":"t3","data":{"title":"Post A",'
    '"permalink":"/r/Music/comments/aaa/post_a/","created_utc":1767225600}},'
    '{"kind":"t3","data":{"title":"Post B",'
    '"permalink":"/r/Music/comments/bbb/post_b/"}},'
    '{"kind":"t3","data":{"no_title_or_permalink":true}},'
    '{"kind":"t3","data":"not a map"}'
    ']}}';

const String _botPageHtml = '<!doctype html><html><head><title>Blocked'
    '</title></head><body><p>whoa there, pardner</p></body></html>';

void main() {
  group('RedditClient.newPosts (valid JSON listing)', () {
    test('parses posts, joins permalinks and skips malformed children',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final requests = <http.Request>[];
      final client = RedditClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(_listingBody, 200);
          }),
        ),
      );

      final result = await client.newPosts(subreddit: 'Music', limit: 5);

      final posts = _ok(result).value;
      expect(posts, hasLength(2));

      expect(posts[0].title, 'Post A');
      expect(posts[0].permalinkUrl,
          'https://www.reddit.com/r/Music/comments/aaa/post_a/');
      // created_utc seconds → UTC instant.
      expect(posts[0].createdUtc, DateTime.utc(2026, 1, 1));
      expect(posts[0].createdUtc!.isUtc, isTrue);

      expect(posts[1].title, 'Post B');
      expect(posts[1].permalinkUrl,
          'https://www.reddit.com/r/Music/comments/bbb/post_b/');
      expect(posts[1].createdUtc, isNull);

      expect(requests.single.url.host, 'www.reddit.com');
      expect(requests.single.url.path, '/r/Music/new.json');
      expect(requests.single.url.queryParameters['limit'], '5');
    });

    test('defaults to /r/Music with limit 20', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final requests = <http.Request>[];
      final client = RedditClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async {
            requests.add(request);
            return http.Response('{"data":{"children":[]}}', 200);
          }),
        ),
      );

      await client.newPosts();

      expect(requests.single.url.path, '/r/Music/new.json');
      expect(requests.single.url.queryParameters['limit'], '20');
    });

    test('missing children node parses to an empty success', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = RedditClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async => http.Response('{}', 200)),
        ),
      );

      final result = await client.newPosts();

      expect(result.isSuccess, isTrue);
      expect(_ok(result).value, isEmpty);
    });
  });

  group('RedditClient bot-page degradation', () {
    test('HTML bot page (non-JSON body) resolves to the documented '
        'parsing failure', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = RedditClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          // The live verification got an HTML page with 200 OK and a
          // text/html content type — the client validates the BODY shape.
          client: MockClient((request) async => http.Response(
                _botPageHtml,
                200,
                headers: <String, String>{'content-type': 'text/html'},
              )),
        ),
      );

      final result = await client.newPosts();

      expect(result.isErr, isTrue);
      final failure = _err(result).failure;
      expect(failure, isA<ParsingFailure>());
      expect(failure.message, 'reddit blocked (non-JSON response)');
    });

    test('leading whitespace before a non-JSON payload is also detected',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = RedditClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient(
              (request) async => http.Response('  <html>bot</html>', 200)),
        ),
      );

      final result = await client.newPosts();

      expect(_err(result).failure.message,
          'reddit blocked (non-JSON response)');
    });

    test('JSON payload that does not start with { (e.g. an array) is '
        'treated as blocked, not as a listing', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = RedditClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async => http.Response('[1,2]', 200)),
        ),
      );

      final result = await client.newPosts();

      expect(_err(result).failure.message,
          'reddit blocked (non-JSON response)');
    });
  });

  test('malformed JSON after a valid { start maps to Failure.parsing',
      () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final client = RedditClient(
      http: CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async => http.Response('{"data":', 200)),
      ),
    );

    final result = await client.newPosts();

    expect(_err(result).failure, isA<ParsingFailure>());
    expect(_err(result).failure.message, contains('Malformed Reddit'));
  });

  test('HTTP failure is surfaced as Failure.network', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final client = RedditClient(
      http: CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async => http.Response('no', 403)),
      ),
    );

    final result = await client.newPosts();

    expect(_err(result).failure, isA<NetworkFailure>());
    expect(_err(result).failure.message, contains('403'));
  });
}

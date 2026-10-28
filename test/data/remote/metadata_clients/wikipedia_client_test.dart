// authored, awaiting local run.
//
// Contract tests for lib/data/remote/metadata_clients/wikipedia_client.dart:
// summary parsing (title/extract/thumbnail), the space→underscore slug
// mapping, empty/absent summaries and error mapping.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/remote/metadata_clients/wikipedia_client.dart';
import 'package:wavely/data/remote/metadata_http.dart';

AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

Success<T> _ok<T>(Result<T> result) => result as Success<T>;
Err<T> _err<T>(Result<T> result) => result as Err<T>;

const String _summaryBody =
    '{"type":"standard","title":"New Order",'
    '"displaytitle":"New Order",'
    '"extract":"New Order are an English rock band formed in 1980.",'
    '"thumbnail":{"source":"https://upload.wikimedia.org/lead.jpg",'
    '"width":200,"height":200}}';

void main() {
  test('parses title, extract and thumbnail; slug maps spaces to underscores',
      () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final requests = <http.Request>[];
    final client = WikipediaClient(
      http: CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(_summaryBody, 200);
        }),
      ),
    );

    final result = await client.summary('New Order');

    final summary = _ok(result).value;
    expect(summary, isNotNull);
    expect(summary!.title, 'New Order');
    expect(summary.extract, contains('English rock band'));
    expect(summary.thumbnailUrl, 'https://upload.wikimedia.org/lead.jpg');

    expect(requests.single.url.host, 'en.wikipedia.org');
    expect(
      requests.single.url.path,
      '/api/rest_v1/page/summary/New_Order',
    );
  });

  test('summary without a thumbnail has a null thumbnailUrl', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    const body =
        '{"type":"standard","title":"X","extract":"Some text."}';
    final client = WikipediaClient(
      http: CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async => http.Response(body, 200)),
      ),
    );

    final result = await client.summary('X');

    final summary = _ok(result).value;
    expect(summary!.thumbnailUrl, isNull);
  });

  test('page without a usable summary (no extract) resolves to null success',
      () async {
    final db = _memoryDb();
    addTearDown(db.close);
    const body = '{"type":"disambiguation","title":"Mercury"}';
    final client = WikipediaClient(
      http: CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async => http.Response(body, 200)),
      ),
    );

    final result = await client.summary('Mercury');

    expect(result.isSuccess, isTrue);
    expect(_ok(result).value, isNull);
  });

  test('thumbnail without a source string is ignored', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    const body =
        '{"title":"X","extract":"Text","thumbnail":{"width":100}}';
    final client = WikipediaClient(
      http: CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async => http.Response(body, 200)),
      ),
    );

    final result = await client.summary('X');

    expect(_ok(result).value!.thumbnailUrl, isNull);
  });

  test('malformed JSON maps to Failure.parsing', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final client = WikipediaClient(
      http: CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient(
            (request) async => http.Response('<html>blocked</html>', 200)),
      ),
    );

    final result = await client.summary('X');

    expect(_err(result).failure, isA<ParsingFailure>());
    expect(_err(result).failure.message, contains('Malformed Wikipedia'));
  });

  test('non-map payload maps to Failure.parsing (unexpected payload)',
      () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final client = WikipediaClient(
      http: CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async => http.Response('"str"', 200)),
      ),
    );

    final result = await client.summary('X');

    expect(_err(result).failure, isA<ParsingFailure>());
    expect(_err(result).failure.message, contains('Unexpected Wikipedia'));
  });

  test('HTTP failure is surfaced as Failure.network', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final client = WikipediaClient(
      http: CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async => http.Response('gone', 404)),
      ),
    );

    final result = await client.summary('X');

    expect(_err(result).failure, isA<NetworkFailure>());
    expect(_err(result).failure.message, contains('404'));
  });
}

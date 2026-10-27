// authored, awaiting local run.
//
// Contract tests for lib/data/remote/metadata_clients/archive_org_client.dart:
// advancedsearch parsing (identifier/title, multi-value title lists, docs
// skipping), the manually built query string (duplicate fl[] keys cannot go
// through Uri.replace), and error mapping.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/remote/metadata_clients/archive_org_client.dart';

AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

Success<T> _ok<T>(Result<T> result) => result as Success<T>;
Err<T> _err<T>(Result<T> result) => result as Err<T>;

const String _searchBody =
    '{"responseHeader":{"status":0,"QTime":7},"response":{"numFound":4,'
    '"start":0,"docs":['
    '{"identifier":"grateful-dead-1977","title":"Grateful Dead 1977"},'
    '{"identifier":"multi-title","title":["", "Second Title", "Third"]},'
    '{"title":"missing identifier"},'
    '{"identifier":"no-title"}'
    ']}}';

void main() {
  test('parses docs, takes the first non-empty title, skips id-less rows',
      () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final requests = <http.Request>[];
    final client = ArchiveOrgClient(
      http: CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(_searchBody, 200);
        }),
      ),
    );

    final result = await client.search('grateful dead', rows: 4);

    final items = _ok(result).value;
    expect(items, hasLength(3));

    expect(items[0].identifier, 'grateful-dead-1977');
    expect(items[0].title, 'Grateful Dead 1977');

    // Multi-valued title: first NON-EMPTY entry wins.
    expect(items[1].identifier, 'multi-title');
    expect(items[1].title, 'Second Title');

    expect(items[2].identifier, 'no-title');
    expect(items[2].title, isNull);
  });

  test('query string carries the duplicate fl[] keys (built manually, not '
      'via Uri.replace)', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final requests = <http.Request>[];
    final client = ArchiveOrgClient(
      http: CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(_searchBody, 200);
        }),
      ),
    );

    await client.search('cool jams & more', rows: 3);

    final url = requests.single.url;
    expect(url.host, 'archive.org');
    expect(url.path, '/advancedsearch.php');
    // Spaces are encoded; the raw string keeps BOTH fl[] entries.
    expect(
      url.query,
      contains('q=cool+jams+%26+more'),
    );
    expect(
      url.toString(),
      contains('fl[]=identifier&fl[]=title'),
    );
    expect(url.queryParametersAll['fl[]'],
        <String>['identifier', 'title']);
    expect(url.queryParametersAll['q'], <String>['cool jams & more']);
    expect(url.queryParameters['rows'], '3');
    expect(url.queryParameters['page'], '1');
    expect(url.queryParameters['output'], 'json');
  });

  test('empty docs list parses to an empty success', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final client = ArchiveOrgClient(
      http: CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient(
            (request) async => http.Response('{"response":{}}', 200)),
      ),
    );

    final result = await client.search('nothing');

    expect(result.isSuccess, isTrue);
    expect(_ok(result).value, isEmpty);
  });

  test('malformed JSON maps to Failure.parsing', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final client = ArchiveOrgClient(
      http: CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async => http.Response('{oops', 200)),
      ),
    );

    final result = await client.search('x');

    expect(_err(result).failure, isA<ParsingFailure>());
    expect(_err(result).failure.message, contains('Malformed archive.org'));
  });

  test('non-map payload maps to Failure.parsing', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final client = ArchiveOrgClient(
      http: CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async => http.Response('"nope"', 200)),
      ),
    );

    final result = await client.search('x');

    expect(_err(result).failure, isA<ParsingFailure>());
    expect(_err(result).failure.message, contains('Unexpected archive.org'));
  });

  test('HTTP failure is surfaced as Failure.network', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final client = ArchiveOrgClient(
      http: CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async => http.Response('slow', 503)),
      ),
    );

    final result = await client.search('x');

    expect(_err(result).failure, isA<NetworkFailure>());
    expect(_err(result).failure.message, contains('503'));
  });
}

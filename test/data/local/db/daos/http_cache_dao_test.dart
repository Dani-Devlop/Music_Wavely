/// Authored, awaiting local run.
///
/// No Flutter/Dart SDK exists in the authoring sandbox, so this suite has
/// never been executed. It targets the real `HttpCacheDao` API in `lib/`
/// and needs `dart run build_runner build` first (generates
/// `app_database.g.dart` and the DAO mixins).
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/http_cache_dao.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  group('requestKey', () {
    test('is deterministic for method + url', () {
      final a = HttpCacheDao.requestKey('GET', 'https://api.example.com/x');
      final b = HttpCacheDao.requestKey('GET', 'https://api.example.com/x');

      expect(a, b);
    });

    test('differs per url and per method', () {
      final base = HttpCacheDao.requestKey('GET', 'https://api.example.com/x');

      expect(
        base,
        isNot(HttpCacheDao.requestKey('GET', 'https://api.example.com/y')),
      );
      expect(
        base,
        isNot(HttpCacheDao.requestKey('POST', 'https://api.example.com/x')),
      );
    });

    test('is a 64-char lowercase sha256 hex digest', () {
      final key = HttpCacheDao.requestKey('GET', 'https://api.example.com/x');

      expect(key, hasLength(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key), isTrue);
    });
  });

  group('put / get / prune', () {
    test('get returns null for keys that were never put', () async {
      expect(await db.httpCacheDao.get('missing'), isNull);
    });

    test('put stores the body and metadata; get returns it before expiry',
        () async {
      final key = HttpCacheDao.requestKey('GET', 'https://api.example.com/x');

      await db.httpCacheDao.put(
        requestKey: key,
        body: '{"result": [1, 2, 3]}',
        statusCode: 200,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(await db.httpCacheDao.get(key), '{"result": [1, 2, 3]}');

      final row = await db.select(db.httpCache).getSingle();
      expect(row.statusCode, 200);
      expect(row.fetchedAt, isNotNull);
    });

    test('expired entries read as null (stale bodies are never served)',
        () async {
      final key = HttpCacheDao.requestKey('GET', 'https://api.example.com/x');

      await db.httpCacheDao.put(
        requestKey: key,
        body: 'stale',
        statusCode: 200,
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );

      expect(await db.httpCacheDao.get(key), isNull);
    });

    test('put overwrites an existing entry in place', () async {
      final key = HttpCacheDao.requestKey('GET', 'https://api.example.com/x');

      await db.httpCacheDao.put(
        requestKey: key,
        body: 'old',
        statusCode: 200,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await db.httpCacheDao.put(
        requestKey: key,
        body: 'new',
        statusCode: 304,
        expiresAt: DateTime.now().add(const Duration(hours: 2)),
      );

      final rows = await db.select(db.httpCache).get();
      expect(rows, hasLength(1));
      expect(rows.single.body, 'new');
      expect(rows.single.statusCode, 304);
      expect(await db.httpCacheDao.get(key), 'new');
    });

    test('prune deletes only expired rows and reports how many', () async {
      Future<void> put(String url, DateTime expiresAt) =>
          db.httpCacheDao.put(
            requestKey:
                HttpCacheDao.requestKey('GET', 'https://api.example.com$url'),
            body: 'body-$url',
            statusCode: 200,
            expiresAt: expiresAt,
          );

      await put('/fresh1', DateTime.now().add(const Duration(hours: 1)));
      await put('/fresh2', DateTime.now().add(const Duration(hours: 1)));
      await put('/stale1', DateTime.now().subtract(const Duration(hours: 1)));
      await put('/stale2', DateTime.now().subtract(const Duration(hours: 1)));

      expect(await db.httpCacheDao.prune(), 2);

      final remaining = await db.select(db.httpCache).get();
      expect(remaining, hasLength(2));
      expect(
        remaining.map((r) => r.body).toSet(),
        {'body-/fresh1', 'body-/fresh2'},
      );
      expect(await db.httpCacheDao.get(
        HttpCacheDao.requestKey('GET', 'https://api.example.com/stale1'),
      ), isNull);
    });
  });
}

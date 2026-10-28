// authored, awaiting local run.
//
// Contract tests for lib/data/remote/metadata_http.dart:
// MetadataHttp.userAgent, RateLimiter (turnstile spacing with an injected
// clock) and CachingHttpClient (UA propagation, read-through cache write /
// hit, TTL expiry re-fetch, stale-while-error, non-200 mapping, ttlFor
// override, UTF-8 body decoding, storage-failure resilience).
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/http_cache_dao.dart';
import 'package:wavely/data/remote/metadata_http.dart';

Success<String> _ok(Result<String> result) => result as Success<String>;
Err<String> _err(Result<String> result) => result as Err<String>;

AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

http.Response _json(String body, [int status = 200]) =>
    http.Response(body, status, headers: <String, String>{
      'content-type': 'application/json',
    });

void main() {
  group('MetadataHttp.userAgent', () {
    test('is the canonical MusicBrainz-style UA', () {
      expect(
        MetadataHttp.userAgent,
        'Wavely/1.0 (https://github.com/Dani-Devlop/Music_Wavely)',
      );
    });
  });

  group('CachingHttpClient', () {
    test('sends the canonical UA header on every network request and lets '
        'extra headers merge on top', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final requests = <http.Request>[];
      final client = CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async {
          requests.add(request);
          return _json('{}');
        }),
      );

      await client.getJson(
        Uri.parse('https://example.org/plain'),
        ttl: const Duration(hours: 1),
      );
      await client.getJson(
        Uri.parse('https://example.org/with-extras'),
        ttl: const Duration(hours: 1),
        extraHeaders: <String, String>{
          'x-trace': 't1',
          'user-agent': 'Custom/2.0',
        },
      );

      expect(requests, hasLength(2));
      expect(requests[0].headers['user-agent'], MetadataHttp.userAgent);
      expect(requests[1].headers['user-agent'], 'Custom/2.0');
      expect(requests[1].headers['x-trace'], 't1');
    });

    test('caches a 200 and serves an identical GET without a second call',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      var calls = 0;
      final client = CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async {
          calls++;
          return _json('{"body": $calls}');
        }),
      );
      final url = Uri.parse('https://example.org/a.json');
      const ttl = Duration(hours: 6);

      final first = await client.getJson(url, ttl: ttl);
      final second = await client.getJson(url, ttl: ttl);

      expect(_ok(first).value, '{"body": 1}');
      expect(_ok(second).value, '{"body": 1}');
      expect(calls, 1);

      // The row landed in the persistent store under the dao's request key.
      final row = await (db.select(db.httpCache)
            ..where(
              (r) => r.requestKey
                  .equals(HttpCacheDao.requestKey('GET', url.toString())),
            ))
          .getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.body, '{"body": 1}');
      expect(row.statusCode, 200);
    });

    test('expired TTL re-fetches and overwrites the cached body', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      var now = DateTime(2026, 6, 1, 12);
      var calls = 0;
      final client = CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async {
          calls++;
          return _json('{"gen": $calls}');
        }),
        now: () => now,
      );
      final url = Uri.parse('https://example.org/a.json');
      const ttl = Duration(hours: 6);

      expect(_ok(await client.getJson(url, ttl: ttl)).value, '{"gen": 1}');

      now = now.add(const Duration(hours: 6, seconds: 1));
      expect(_ok(await client.getJson(url, ttl: ttl)).value, '{"gen": 2}');
      expect(calls, 2);
    });

    test('fresh entry inside TTL does not touch the network', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      var now = DateTime(2026, 6, 1, 12);
      var calls = 0;
      final client = CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async {
          calls++;
          return _json('ok');
        }),
        now: () => now,
      );
      final url = Uri.parse('https://example.org/a.json');

      await client.getJson(url, ttl: const Duration(hours: 6));
      now = now.add(const Duration(hours: 5, minutes: 59));
      await client.getJson(url, ttl: const Duration(hours: 6));

      expect(calls, 1);
    });

    test('stale-while-error: expired cache is served when the network throws',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      var now = DateTime(2026, 6, 1, 12);
      var offline = false;
      final client = CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async {
          if (offline) {
            throw http.ClientException('device offline');
          }
          return _json('{"cached": true}');
        }),
        now: () => now,
      );
      final url = Uri.parse('https://example.org/a.json');
      const ttl = Duration(hours: 1);

      expect(_ok(await client.getJson(url, ttl: ttl)).value,
          '{"cached": true}');

      // TTL expired AND the request throws — the stale body still wins.
      now = now.add(const Duration(days: 30));
      offline = true;
      final stale = await client.getJson(url, ttl: ttl);
      expect(_ok(stale).value, '{"cached": true}');
    });

    test('network error with no cached row is Failure.network', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async {
          throw http.ClientException('DNS failure');
        }),
      );

      final result = await client.getJson(
        Uri.parse('https://example.org/never.json'),
        ttl: const Duration(hours: 1),
      );

      final failure = _err(result).failure;
      expect(failure, isA<NetworkFailure>());
      expect(failure.message, contains('Request failed'));
    });

    test('non-200 maps to Failure.network and is never cached', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      var calls = 0;
      final client = CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async {
          calls++;
          return _json('{"error": "rate limited"}', 429);
        }),
      );
      final url = Uri.parse('https://example.org/a.json');
      const ttl = Duration(hours: 1);

      final result = await client.getJson(url, ttl: ttl);
      expect(result.isErr, isTrue);
      expect(_err(result).failure, isA<NetworkFailure>());
      expect(_err(result).failure.message, contains('429'));

      // Not cached: the next call hits the network again.
      await client.getJson(url, ttl: ttl);
      expect(calls, 2);

      final stored = await (db.select(db.httpCache)
            ..where(
              (r) => r.requestKey
                  .equals(HttpCacheDao.requestKey('GET', url.toString())),
            ))
          .getSingleOrNull();
      expect(stored, isNull);
    });

    test('non-200 after TTL expiry does NOT fall back to the stale row',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      var now = DateTime(2026, 6, 1, 12);
      var failing = false;
      final client = CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async {
          if (failing) {
            return _json('server error', 500);
          }
          return _json('{"good": true}');
        }),
        now: () => now,
      );
      final url = Uri.parse('https://example.org/a.json');
      const ttl = Duration(hours: 1);

      expect(_ok(await client.getJson(url, ttl: ttl)).value,
          '{"good": true}');

      now = now.add(const Duration(days: 2));
      failing = true;
      final result = await client.getJson(url, ttl: ttl);
      // The server ANSWERED, so its error document is not cached data.
      expect(result.isErr, isTrue);
      expect(_err(result).failure, isA<NetworkFailure>());
    });

    test('ttlFor overrides the per-call ttl for matching URLs', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final now = DateTime(2026, 6, 1, 12);
      final client = CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async => _json('{}')),
        ttlFor: (url) => url.host == 'slow.example.org'
            ? const Duration(hours: 24)
            : const Duration(minutes: 5),
        now: () => now,
      );

      await client.getJson(
        Uri.parse('https://slow.example.org/x'),
        ttl: const Duration(hours: 1),
      );
      await client.getJson(
        Uri.parse('https://fast.example.org/x'),
        ttl: const Duration(hours: 1),
      );

      final rows = await db.select(db.httpCache).get();
      expect(rows, hasLength(2));
      for (final row in rows) {
        final expected = row.requestKey ==
                HttpCacheDao.requestKey('GET', 'https://slow.example.org/x')
            ? now.add(const Duration(hours: 24))
            : now.add(const Duration(minutes: 5));
        expect(row.expiresAt, expected);
      }
    });

    test('decodes UTF-8 bodies even without a charset header', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = CachingHttpClient(
        cacheDao: db.httpCacheDao,
        client: MockClient((request) async => http.Response.bytes(
              const <int>[
                0x7b, 0x22, 0x74, 0x22, 0x3a, 0x22, 0x63, 0x61, 0x66, //
                0xc3, 0xa9, 0x22, 0x7d, // {"t":"café"}
              ],
              200,
            )),
      );

      final result = await client.getJson(
        Uri.parse('https://example.org/x'),
        ttl: const Duration(hours: 1),
      );

      expect(_ok(result).value, '{"t":"café"}');
    });

    test('storage failures never mask a good response', () async {
      // A dao bound to an already-closed database makes BOTH the cached read
      // and the cache write throw; the live response must still win and the
      // call must stay a success.
      final brokenDb = AppDatabase(NativeDatabase.memory());
      await brokenDb.close();
      var calls = 0;
      final client = CachingHttpClient(
        cacheDao: brokenDb.httpCacheDao,
        client: MockClient((request) async {
          calls++;
          return _json('{"live": $calls}');
        }),
      );
      final url = Uri.parse('https://example.org/x');
      const ttl = Duration(hours: 1);

      final first = await client.getJson(url, ttl: ttl);
      final second = await client.getJson(url, ttl: ttl);

      expect(_ok(first).value, '{"live": 1}');
      expect(_ok(second).value, '{"live": 2}');
      expect(calls, 2); // nothing was persisted, so no cache hit is possible
    });
  });

  group('RateLimiter (turnstile)', () {
    test('first turn completes immediately without scheduling a timer', () {
      fakeAsync((async) {
        final limiter = RateLimiter(
          const Duration(seconds: 1),
          now: () => DateTime(2026).add(async.elapsed),
        );
        var completed = false;
        unawaited(
          limiter.waitTurn().then((_) => completed = true),
        );
        async.flushMicrotasks();
        expect(completed, isTrue);
        expect(async.periodicTimerCount, 0);
        expect(async.nonPeriodicTimerCount, 0);
      });
    });

    test('second turn waits at least minInterval after the first start', () {
      fakeAsync((async) {
        final stamps = <DateTime>[];
        final limiter = RateLimiter(
          const Duration(seconds: 1),
          now: () => DateTime(2026).add(async.elapsed),
        );
        unawaited(
          limiter.waitTurn().then((_) => stamps.add(DateTime(2026)
              .add(async.elapsed))),
        );
        async.flushMicrotasks();
        unawaited(
          limiter.waitTurn().then((_) => stamps.add(DateTime(2026)
              .add(async.elapsed))),
        );
        async.flushMicrotasks();
        expect(stamps, hasLength(1));

        async.elapse(const Duration(milliseconds: 400));
        expect(stamps, hasLength(1)); // still waiting
        async.elapse(const Duration(milliseconds: 600));

        expect(stamps, hasLength(2));
        final spacing = stamps[1].difference(stamps[0]);
        expect(spacing, const Duration(seconds: 1));
      });
    });

    test('a turn after several intervals completes without waiting', () {
      fakeAsync((async) {
        final limiter = RateLimiter(
          const Duration(seconds: 1),
          now: () => DateTime(2026).add(async.elapsed),
        );
        unawaited(limiter.waitTurn());
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        var completed = false;
        unawaited(
          limiter.waitTurn().then((_) => completed = true),
        );
        async.flushMicrotasks();
        expect(completed, isTrue);
      });
    });

    test('concurrent callers queue up in call order, spaced by interval',
        () {
      fakeAsync((async) {
        final stamps = <DateTime>[];
        final limiter = RateLimiter(
          const Duration(milliseconds: 100),
          now: () => DateTime(2026).add(async.elapsed),
        );
        for (var i = 0; i < 3; i++) {
          unawaited(
            limiter.waitTurn().then((_) => stamps.add(DateTime(2026)
                .add(async.elapsed))),
          );
        }
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 250));

        expect(stamps, hasLength(3));
        expect(stamps[0].isBefore(stamps[1]), isTrue);
        expect(stamps[1].isBefore(stamps[2]), isTrue);
        expect(
          stamps[1].difference(stamps[0]),
          const Duration(milliseconds: 100),
        );
        expect(
          stamps[2].difference(stamps[1]),
          const Duration(milliseconds: 100),
        );
      });
    });

    test('waitTurn never throws across many sequential turns', () async {
      final limiter = RateLimiter(
        Duration.zero,
        now: () => DateTime(2026),
      );
      final order = <int>[];
      for (var i = 0; i < 5; i++) {
        await limiter.waitTurn();
        order.add(i);
      }
      expect(order, <int>[0, 1, 2, 3, 4]);
    });
  });

  group('HttpCacheDao.requestKey', () {
    test('is deterministic per method+url and distinct otherwise', () {
      final a = HttpCacheDao.requestKey('GET', 'https://example.org/x');
      final b = HttpCacheDao.requestKey('GET', 'https://example.org/x');
      final c = HttpCacheDao.requestKey('GET', 'https://example.org/y');
      final d = HttpCacheDao.requestKey('POST', 'https://example.org/x');
      expect(a, b);
      expect(a, isNot(c));
      expect(a, isNot(d));
    });
  });
}

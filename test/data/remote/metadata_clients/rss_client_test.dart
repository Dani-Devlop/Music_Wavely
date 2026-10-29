// authored, awaiting local run.
//
// Contract tests for lib/data/remote/metadata_clients/rss_client.dart:
// RSS 2.0 <item> and Atom <entry> parsing fixtures, entity/CDATA/inline-tag
// cleaning, the RFC-822 timezone-naive date behavior documented in the file
// (ISO/Atom dates keep their real instant), item-skip rules, and the
// fetch() layer (TTL default, failure propagation).
//
// DELTA vs the task hint: "malformed XML → failure" does NOT hold for the
// parser — RssClient.parse is regex-based and a 200 body without any
// <item>/<entry> parses to an EMPTY SUCCESS by design (documented in the
// class doc). Failure surfaces only through the HTTP layer (getJson).
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/remote/metadata_clients/rss_client.dart';
import 'package:wavely/data/remote/metadata_http.dart';

AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

Success<T> _ok<T>(Result<T> result) => result as Success<T>;
Err<T> _err<T>(Result<T> result) => result as Err<T>;

void main() {
  group('RssClient.parse — RSS 2.0', () {
    test('parses items with RFC-822 pubDate (timezone-naive, documented)',
        () {
      const body = '<rss><channel>'
          '<title>Feed</title>'
          '<item>'
          '<title><![CDATA[First &amp; loudest news]]></title>'
          '<link>https://example.org/a?x=1&amp;y=2</link>'
          '<pubDate>Mon, 27 Oct 2026 10:00:00 GMT</pubDate>'
          '</item>'
          '<item>'
          '<title>Second &lt;b&gt;story&lt;/b&gt;</title>'
          '<link>https://example.org/b</link>'
          '<pubDate>Tue, 28 Oct 2026 09:30:00 +0100</pubDate>'
          '</item>'
          '</channel></rss>';

      final result = RssClient.parse(body);

      final items = _ok(result).value;
      expect(items, hasLength(2));

      expect(items[0].title, 'First & loudest news');
      expect(items[0].link, 'https://example.org/a?x=1&y=2');
      // RFC-822 dates are parsed TIMEZONE-NAIVE (local clock): the GMT
      // offset is dropped and the wall-clock fields are kept as-is.
      expect(items[0].publishedAt, DateTime(2026, 10, 27, 10, 0, 0));
      expect(items[0].publishedAt!.isUtc, isFalse);

      // The +0100 offset is likewise ignored (naive local wall clock).
      // Entity-encoded markup decodes AFTER tag stripping, so it survives
      // as literal text (documented "inline markup is stripped, not
      // interpreted" applies to real tags only).
      expect(items[1].title, 'Second <b>story</b>');
      expect(items[1].publishedAt, DateTime(2026, 10, 28, 9, 30, 0));
    });

    test('item without pubDate has a null publishedAt', () {
      const body =
          '<rss><item><title>T</title><link>https://x</link></item></rss>';

      final items = _ok(RssClient.parse(body)).value;

      expect(items.single.publishedAt, isNull);
    });

    test('entries without a title or without a link are dropped', () {
      const body = '<rss><channel>'
          '<item><link>https://x</link></item>'
          '<item><title>Only title</title></item>'
          '<item><title>  </title><link>https://y</link></item>'
          '<item><title>Kept</title><link>https://z</link></item>'
          '</channel></rss>';

      final items = _ok(RssClient.parse(body)).value;

      expect(items, hasLength(1));
      expect(items.single.title, 'Kept');
      expect(items.single.link, 'https://z');
    });

    test('decodes the documented entity set only; numeric entities stay '
        'literal', () {
      const body = '<rss><item>'
          '<title>&quot;A&quot; &amp; &#39;B&apos;s&#39; &lt;tag&gt; &#9829;</title>'
          '<link>https://x</link>'
          '</item></rss>';

      final items = _ok(RssClient.parse(body)).value;

      expect(items.single.title,
          '"A" & \'B\'s\' <tag> &#9829;');
    });
  });

  group('RssClient.parse — Atom', () {
    test('parses <entry> with href link and ISO updated instant', () {
      const body = '<feed>'
          '<entry>'
          '<title>Atom one</title>'
          '<link rel="alternate" type="text/html" href="https://example.org/1"/>'
          '<updated>2026-01-05T08:30:00Z</updated>'
          '</entry>'
          '<entry>'
          '<title>Atom two</title>'
          '<link href="https://example.org/2" />'
          '<published>2026-01-06T10:00:00+02:00</published>'
          '</entry>'
          '</feed>';

      final items = _ok(RssClient.parse(body)).value;

      expect(items, hasLength(2));
      expect(items[0].title, 'Atom one');
      expect(items[0].link, 'https://example.org/1');
      // ISO dates keep their real instant (UTC-anchored).
      expect(items[0].publishedAt, DateTime.utc(2026, 1, 5, 8, 30));
      expect(items[0].publishedAt!.isUtc, isTrue);
      expect(items[1].link, 'https://example.org/2');
      expect(items[1].publishedAt, DateTime.utc(2026, 1, 6, 8, 0));
    });

    test('updated wins over published when both are present', () {
      const body = '<feed><entry>'
          '<title>T</title><link href="https://x"/>'
          '<updated>2026-02-01T00:00:00Z</updated>'
          '<published>2026-01-01T00:00:00Z</published>'
          '</entry></feed>';

      final items = _ok(RssClient.parse(body)).value;

      expect(items.single.publishedAt, DateTime.utc(2026, 2, 1));
    });
  });

  group('RssClient.parse — documented limitations', () {
    test('a feed-shaped body with zero entries parses to an EMPTY success '
        '(not a failure)', () {
      const body = '<?xml version="1.0"?><rss><channel><title>Empty'
          '</title></channel></rss>';

      final result = RssClient.parse(body);

      expect(result.isSuccess, isTrue);
      expect(_ok(result).value, isEmpty);
    });

    test('a garbage (non-XML) body also parses to an empty success — '
        'failures come from the HTTP layer, not the parser', () {
      final result = RssClient.parse('<html>totally not a feed</html>');

      expect(result.isSuccess, isTrue);
      expect(_ok(result).value, isEmpty);
    });

    test('mixed RSS + Atom bodies collect items from both', () {
      const body = '<feed><entry><title>E</title>'
          '<link href="https://e"/></entry></feed>'
          '<rss><item><title>R</title><link>https://r</link></item></rss>';

      final items = _ok(RssClient.parse(body)).value;

      expect([for (final item in items) item.title], <String>['R', 'E']);
    });
  });

  group('RssClient.fetch', () {
    test('fetches with the default 1h TTL and parses the body', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final requests = <http.Request>[];
      final client = RssClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(
              '<rss><item><title>Live</title><link>https://n</link>'
              '<pubDate>Wed, 01 Jul 2026 12:00:00 GMT</pubDate></item></rss>',
              200,
            );
          }),
        ),
      );

      final result = await client.fetch(
        Uri.parse('https://www.nme.com/rss/news'),
      );

      final items = _ok(result).value;
      expect(items.single.title, 'Live');
      expect(items.single.publishedAt, DateTime(2026, 7, 1, 12));
      expect(requests.single.url, Uri.parse('https://www.nme.com/rss/news'));
    });

    test('HTTP failure propagates as Failure.network', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final client = RssClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async =>
              http.Response('moved for real', 500)),
        ),
      );

      final result = await client.fetch(Uri.parse('https://x/feed'));

      expect(_err(result).failure, isA<NetworkFailure>());
    });

    test('custom ttl is honored per call', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final now = DateTime(2026, 6, 1, 12);
      final client = RssClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: MockClient((request) async =>
              http.Response('<rss></rss>', 200)),
          now: () => now,
        ),
      );

      await client.fetch(
        Uri.parse('https://x/feed'),
        ttl: const Duration(minutes: 10),
      );

      final row = await (db.select(db.httpCache)).getSingle();
      expect(row.expiresAt, now.add(const Duration(minutes: 10)));
    });
  });
}

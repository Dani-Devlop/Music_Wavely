// authored, awaiting local run.
//
// Contract tests for lib/data/remote/metadata_clients/news_service.dart:
// two-feed aggregation sorted newest-first (undated last), partial failure
// degradation (one feed failing keeps the other), total-failure mapping,
// and the 5-minute memo (injectable clock) incl. forceRefresh bypass.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/remote/metadata_clients/news_service.dart';
import 'package:wavely/data/remote/metadata_clients/rss_client.dart';

AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

Success<T> _ok<T>(Result<T> result) => result as Success<T>;
Err<T> _err<T>(Result<T> result) => result as Err<T>;

const String _pitchforkBody = '<rss><channel>'
    '<item><title>Pitchfork old</title><link>https://p/old</link>'
    '<pubDate>Mon, 01 Jun 2026 10:00:00 GMT</pubDate></item>'
    '<item><title>Pitchfork fresh</title><link>https://p/fresh</link>'
    '<pubDate>Wed, 10 Jun 2026 08:00:00 GMT</pubDate></item>'
    '<item><title>Pitchfork undated</title><link>https://p/none</link>'
    '</item>'
    '</channel></rss>';

const String _nmeBody = '<rss><channel>'
    '<item><title>NME newest</title><link>https://n/newest</link>'
    '<pubDate>Thu, 11 Jun 2026 09:00:00 GMT</pubDate></item>'
    '<item><title>NME older</title><link>https://n/older</link>'
    '<pubDate>Tue, 02 Jun 2026 12:00:00 GMT</pubDate></item>'
    '</channel></rss>';

http.Client _fakeNewsHttp({
  required List<Uri> log,
  bool pitchforkFails = false,
  bool nmeFails = false,
}) =>
    MockClient((request) async {
      log.add(request.url);
      if (request.url.host == 'pitchfork.com') {
        return pitchforkFails
            ? http.Response('boom', 500)
            : http.Response(_pitchforkBody, 200);
      }
      if (request.url.host == 'www.nme.com') {
        return nmeFails ? http.Response('boom', 500) : http.Response(
            _nmeBody, 200);
      }
      return http.Response('not found', 404);
    });

NewsService _service(
  AppDatabase db, {
  bool pitchforkFails = false,
  bool nmeFails = false,
  DateTime Function()? now,
  List<Uri>? log,
}) =>
    NewsService(
      rss: RssClient(
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: _fakeNewsHttp(
            log: log ?? <Uri>[],
            pitchforkFails: pitchforkFails,
            nmeFails: nmeFails,
          ),
        ),
      ),
      now: now,
    );

void main() {
  test('aggregates both feeds, labels sources and sorts newest first '
      '(undated last)', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final log = <Uri>[];
    final service = _service(db, log: log);

    final result = await service.headlines();

    final items = _ok(result).value;
    expect(items, hasLength(5));
    // Newest first across BOTH feeds; the undated item goes last.
    expect(
      [for (final item in items) item.title],
      <String>[
        'NME newest', // 2026-06-11 09:00
        'Pitchfork fresh', // 2026-06-10 08:00
        'NME older', // 2026-06-02 12:00
        'Pitchfork old', // 2026-06-01 10:00
        'Pitchfork undated', // undated → last
      ],
    );
  });

  test('each item carries its feed source label and absolute url', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final service = _service(db);

    final items = _ok(await service.headlines()).value;

    final fresh =
        items.singleWhere((item) => item.title == 'Pitchfork fresh');
    expect(fresh.source, 'Pitchfork');
    expect(fresh.url, 'https://p/fresh');
    expect(fresh.publishedAt, DateTime(2026, 6, 10, 8));

    final newest = items.singleWhere((item) => item.title == 'NME newest');
    expect(newest.source, 'NME');
    expect(newest.url, 'https://n/newest');
  });

  test('both documented feeds are requested (Pitchfork + NME)', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final log = <Uri>[];
    final service = _service(db, log: log);

    await service.headlines();

    expect(NewsService.feeds, hasLength(2));
    expect(
      [for (final (source, _) in NewsService.feeds) source],
      <String>['Pitchfork', 'NME'],
    );
    expect(
      [for (final uri in log) uri.host]..sort(),
      <String>['pitchfork.com', 'www.nme.com']..sort(),
    );
  });

  test('ONE failing feed degrades gracefully — the other still contributes',
      () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final service = _service(db, pitchforkFails: true);

    final result = await service.headlines();

    final items = _ok(result).value;
    expect(items, hasLength(2));
    expect([for (final item in items) item.source], everyElement('NME'));
  });

  test('BOTH feeds failing resolves to a Failure', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final service = _service(db, pitchforkFails: true, nmeFails: true);

    final result = await service.headlines();

    expect(result.isErr, isTrue);
    expect(_err(result).failure, isA<NetworkFailure>());
  });

  test('results are memoized for 5 minutes (no refetch)', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    var now = DateTime(2026, 6, 15, 12);
    final log = <Uri>[];
    final service = _service(db, log: log, now: () => now);

    await service.headlines();
    await service.headlines();
    now = now.add(const Duration(minutes: 4, seconds: 59));
    await service.headlines();

    expect(log, hasLength(2)); // one request per feed, once
  });

  test('memo expires after minRefetchInterval — a later call refetches',
      () async {
    final db = _memoryDb();
    addTearDown(db.close);
    var now = DateTime(2026, 6, 15, 12);
    final log = <Uri>[];
    final service = _service(db, log: log, now: () => now);

    await service.headlines();
    now = now.add(NewsService.minRefetchInterval);
    now = now.add(const Duration(seconds: 1));
    await service.headlines();

    expect(log, hasLength(4));
  });

  test('forceRefresh bypasses the memo (pull-to-refresh) and refreshes the '
      'memo stamp', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    var now = DateTime(2026, 6, 15, 12);
    final log = <Uri>[];
    final service = _service(db, log: log, now: () => now);

    await service.headlines();
    await service.headlines(forceRefresh: true);
    now = now.add(const Duration(minutes: 1));
    await service.headlines(); // memo refreshed by the forceRefresh call

    expect(log, hasLength(4));
  });
}

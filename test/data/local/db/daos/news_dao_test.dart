// authored, awaiting local run.
//
// Tests for lib/data/local/db/daos/news_dao.dart over an in-memory
// AppDatabase (schemaVersion 4 creates news_articles + the UNIQUE
// (source, sourceId) index on onCreate): upsert dedupe, ordering,
// category JSON codec and clearAll.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/news_dao.dart';

AppDatabase _db() => AppDatabase(NativeDatabase.memory());

NewsArticlesCompanion _row(
  String sourceId, {
  String source = 'reddit/Music',
  String publishedAt = '2026-03-01T00:00:00.000Z',
  List<String> categories = const <String>['artist_news'],
}) =>
    NewsArticlesCompanion.insert(
      source: source,
      sourceId: sourceId,
      title: 'Title $sourceId',
      summary: 'Summary $sourceId',
      url: 'https://example.com/$sourceId',
      publishedAt: publishedAt,
      categories: NewsCategoryCodec.encode(categories),
      fetchedAt: '2026-03-01T00:00:00.000Z',
    );

void main() {
  late AppDatabase db;

  setUp(() {
    db = _db();
  });

  tearDown(() => db.close());

  group('NewsDao', () {
    test('upsertAll inserts and dedupes on (source, sourceId)', () async {
      await db.newsDao.upsertAll(<NewsArticlesCompanion>[_row('a'), _row('b')]);
      expect(await db.newsDao.allStored(), hasLength(2));

      // Same pair again with an updated title → still 2 rows, title updated.
      await db.newsDao.upsertAll(<NewsArticlesCompanion>[
        NewsArticlesCompanion.insert(
          source: 'reddit/Music',
          sourceId: 'a',
          title: 'UPDATED',
          summary: 'Summary a',
          url: 'https://example.com/a',
          publishedAt: '2026-03-02T00:00:00.000Z',
          categories: NewsCategoryCodec.encode(<String>['artist_news']),
          fetchedAt: '2026-03-02T00:00:00.000Z',
        ),
      ]);
      final List<NewsArticleRow> rows = await db.newsDao.allStored();
      expect(rows, hasLength(2));
      expect(
        rows.firstWhere((r) => r.sourceId == 'a').title,
        'UPDATED',
      );
    });

    test('allStored returns rows and clearAll empties the table', () async {
      await db.newsDao.upsertAll(<NewsArticlesCompanion>[_row('x'), _row('y')]);
      expect(await db.newsDao.allStored(), hasLength(2));
      final int removed = await db.newsDao.clearAll();
      expect(removed, 2);
      expect(await db.newsDao.allStored(), isEmpty);
    });

    test('upsertAll with an empty list is a no-op', () async {
      expect(await db.newsDao.upsertAll(<NewsArticlesCompanion>[]), 0);
    });
  });

  group('NewsCategoryCodec', () {
    test('round-trips category name lists', () {
      const List<String> names = <String>['tech_ai', 'production'];
      expect(NewsCategoryCodec.decode(NewsCategoryCodec.encode(names)), names);
    });

    test('malformed JSON degrades to an empty list', () {
      expect(NewsCategoryCodec.decode('not-json'), isEmpty);
      expect(NewsCategoryCodec.decode('{"a":1}'), isEmpty);
      expect(NewsCategoryCodec.decode('["ok", 3]'), <String>['ok']);
    });
  });
}

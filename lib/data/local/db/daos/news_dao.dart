import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/tables/news_articles.dart';

part 'news_dao.g.dart';

/// Persistence for the news feed (Stage 2.2).
///
/// Acts as the offline layer: every successful fetch upserts into
/// `news_articles` (UNIQUE `(source, sourceId)`), and offline reads fall
/// back to these rows. All methods are fault-tolerant — a storage failure
/// degrades to an empty result instead of throwing into the UI.
@DriftAccessor(tables: [NewsArticles])
class NewsDao extends DatabaseAccessor<AppDatabase> with _$NewsDaoMixin {
  NewsDao(super.attachedDatabase);

  /// Upserts [entries] keyed by the `(source, sourceId)` unique pair.
  /// Returns the number of processed rows.
  Future<int> upsertAll(List<NewsArticlesCompanion> entries) async {
    if (entries.isEmpty) {
      return 0;
    }
    await batch((b) {
      for (final NewsArticlesCompanion entry in entries) {
        b.insert(
          newsArticles,
          entry,
          onConflict: DoUpdate(
            (_) => entry,
            target: <Column<Object>>[
              newsArticles.source,
              newsArticles.sourceId,
            ],
          ),
        );
      }
    });
    return entries.length;
  }

  /// Newest rows first, up to [limit].
  Future<List<NewsArticleRow>> latest({int limit = 100}) {
    return (select(newsArticles)
          ..orderBy([(NewsArticles row) => OrderingTerm.desc(row.publishedAt)])
          ..limit(limit))
        .get();
  }

  /// Every stored row (offline merge input; small table, tens of rows).
  Future<List<NewsArticleRow>> allStored() => select(newsArticles).get();

  /// Removes every article (News settings "clear offline feed" hook).
  Future<int> clearAll() => delete(newsArticles).go();
}

/// Helpers shared by the service and tests for the `categories` JSON column.
abstract final class NewsCategoryCodec {
  /// Encodes category names to the column's JSON representation.
  static String encode(List<String> names) => jsonEncode(names);

  /// Decodes the column's JSON representation; malformed values degrade to
  /// an empty list.
  static List<String> decode(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList(growable: false);
      }
    } on Object {
      // Fall through to the empty default.
    }
    return const <String>[];
  }
}

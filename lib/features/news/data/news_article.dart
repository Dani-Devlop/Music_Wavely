import 'package:drift/drift.dart' show Value;

import 'package:wavely/data/local/db/daos/news_dao.dart';
import 'package:wavely/data/local/db/tables/news_articles.dart';
import 'package:wavely/features/news/data/news_category.dart';

/// In-memory news article model (Stage 2.2).
///
/// Produced by the feed parsers ([NewsService]), classified on arrival and
/// convertible to a drift companion for the offline store.
class NewsArticle {
  /// Creates an article.
  const NewsArticle({
    required this.source,
    required this.sourceId,
    required this.title,
    required this.summary,
    required this.url,
    required this.publishedAt,
    required this.fetchedAt,
    this.imageUrl,
    this.categories = const <NewsCategory>[],
  });

  /// Feed origin label (`reddit`, `pitchfork`, `nme`, custom host).
  final String source;

  /// Stable id inside the source.
  final String sourceId;

  final String title;
  final String summary;

  /// Absolute article URL (https).
  final String url;

  /// Optional article image (absolute https URL).
  final String? imageUrl;

  final DateTime publishedAt;

  /// Timestamp of the fetch that produced this instance.
  final DateTime fetchedAt;

  /// Classifier output at fetch time.
  final List<NewsCategory> categories;

  /// Stable identity used for dedupe: `(source, sourceId)`.
  String get dedupeKey => '$source|$sourceId';

  /// Converts to the drift companion used by [NewsDao.upsertAll].
  NewsArticlesCompanion toCompanion() => NewsArticlesCompanion.insert(
        source: source,
        sourceId: sourceId,
        title: title,
        summary: summary,
        url: url,
        imageUrl: Value<String?>(imageUrl),
        publishedAt: publishedAt.toIso8601String(),
        categories:
            NewsCategoryCodec.encode(categories.map(
              (NewsCategory c) => c.storageName,
            ).toList(growable: false)),
        fetchedAt: fetchedAt.toIso8601String(),
      );

  /// Rebuilds a model from a stored row (offline path).
  factory NewsArticle.fromRow(NewsArticleRow row) {
    final List<NewsCategory> categories = NewsCategoryCodec.decode(
      row.categories,
    ).map(NewsCategory.tryParse).whereType<NewsCategory>().toList();
    return NewsArticle(
      source: row.source,
      sourceId: row.sourceId,
      title: row.title,
      summary: row.summary,
      url: row.url,
      imageUrl: row.imageUrl,
      publishedAt: DateTime.tryParse(row.publishedAt) ?? DateTime.utc(1970),
      fetchedAt: DateTime.tryParse(row.fetchedAt) ?? DateTime.utc(1970),
      categories: categories,
    );
  }
}

import 'package:drift/drift.dart';

/// Persisted news article (Stage 2.2).
///
/// One row per `(source, sourceId)` — the pair is UNIQUE so re-fetches
/// upsert in place instead of duplicating. `categories` is a JSON array of
/// classifier labels (text column: the primitive list type does not exist
/// in this schema; see repo convention). Timestamps are ISO8601 text to
/// match the sync-friendly style of the rest of the schema.
@DataClassName('NewsArticleRow', companion: 'NewsArticlesCompanion')
@TableIndex(
  name: 'idx_news_articles_unique',
  unique: true,
  columns: {#source, #sourceId},
)
class NewsArticles extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Feed origin: `reddit`, `pitchfork`, `nme`, or a custom-RSS host.
  TextColumn get source => text()();

  /// Stable id inside the source (reddit base36 id, RSS guid/link).
  TextColumn get sourceId => text()();

  TextColumn get title => text()();

  /// Plain-text summary (selftext / RSS description, tags stripped).
  TextColumn get summary => text()();

  /// Absolute https article URL.
  TextColumn get url => text()();

  TextColumn get imageUrl => text().nullable()();

  /// ISO8601 publish timestamp.
  TextColumn get publishedAt => text()();

  /// JSON array of [NewsCategory] names, e.g. `["artistNews"]`.
  TextColumn get categories => text()();

  /// ISO8601 timestamp of the last fetch that wrote this row.
  TextColumn get fetchedAt => text()();
}

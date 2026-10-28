import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/app_database.dart';

/// Schema migration version 3 → 4 (Stage 2.2).
///
/// Adds the `news_articles` table (plain CREATE TABLE — no FTS involvement,
/// so no table rebuilds are required; the FTS recreation performed by
/// [AppDatabase.migration] on every upgrade stays harmless).
abstract final class Migration0004 {
  /// Table names created by this migration (used by the migration runner).
  static const List<String> tableNames = <String>['news_articles'];

  /// Runs the migration. drift's generated `createTable` statements come
  /// from the updated [AppDatabase] schema.
  static Future<void> run(Migrator m, AppDatabase db) async {
    await m.createTable(db.newsArticles);
  }
}

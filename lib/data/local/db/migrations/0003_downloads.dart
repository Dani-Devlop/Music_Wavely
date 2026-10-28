import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/app_database.dart';

/// Schema migration version 2 → 3 (Stage 2.1).
///
/// Adds the `downloads` table (plain CREATE TABLE — no FTS involvement, so
/// no table rebuilds are required). The FTS recreation performed by
/// [AppDatabase.migration] on every upgrade stays harmless.
abstract final class Migration0003 {
  /// Table names created by this migration (used by the migration runner).
  static const List<String> tableNames = <String>['downloads'];

  /// Runs the migration. drift's generated `createTable` statements come
  /// from the updated [AppDatabase] schema.
  static Future<void> run(Migrator m, AppDatabase db) async {
    await m.createTable(db.downloads);
  }
}

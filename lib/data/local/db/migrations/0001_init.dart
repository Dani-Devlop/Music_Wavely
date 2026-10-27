import 'package:wavely/data/local/db/app_database.dart';

/// Schema bootstrap (version 1): base tables are created by drift's
/// `createAll()`; this migration only owns the FTS5 full-text index and its
/// sync triggers.
///
/// The virtual table uses the *external content* pattern
/// (`content='tracks'`, `content_rowid='id'`) so tokens are not stored twice.
/// Because FTS5 does not read the content table on its own, the three
/// triggers below keep `tracks_fts` in sync with every INSERT / DELETE /
/// UPDATE on `tracks`; the UPDATE trigger first writes the special
/// `'delete'` command row for the OLD values and then re-inserts the NEW
/// ones, exactly as prescribed by the SQLite FTS5 documentation.
abstract final class Migration0001 {
  /// Creates the external-content FTS5 table over tracks (title/artist/album).
  static const String ftsCreateSql =
      "CREATE VIRTUAL TABLE IF NOT EXISTS tracks_fts USING fts5("
      "title, artist, album, content='tracks', content_rowid='id')";

  /// Name of the AFTER INSERT trigger.
  static const String triggerInsertName = 'trg_tracks_fts_ai';

  /// Name of the AFTER DELETE trigger.
  static const String triggerDeleteName = 'trg_tracks_fts_ad';

  /// Name of the AFTER UPDATE trigger.
  static const String triggerUpdateName = 'trg_tracks_fts_au';

  /// AFTER INSERT trigger: pushes new rows into the FTS index.
  static const String triggerInsertSql =
      'CREATE TRIGGER IF NOT EXISTS $triggerInsertName AFTER INSERT ON tracks '
      'BEGIN '
      'INSERT INTO tracks_fts(rowid, title, artist, album) '
      'VALUES (new.id, new.title, new.artist, new.album); '
      'END';

  /// AFTER DELETE trigger: removes the row from the FTS index using the
  /// special `'delete'` command row required by external-content tables.
  static const String triggerDeleteSql =
      'CREATE TRIGGER IF NOT EXISTS $triggerDeleteName AFTER DELETE ON tracks '
      'BEGIN '
      "INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album) "
      "VALUES ('delete', old.id, old.title, old.artist, old.album); "
      'END';

  /// AFTER UPDATE trigger: deletes the OLD index entry, then inserts the NEW
  /// one (the external-content update pattern).
  static const String triggerUpdateSql =
      'CREATE TRIGGER IF NOT EXISTS $triggerUpdateName AFTER UPDATE ON tracks '
      'BEGIN '
      "INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album) "
      "VALUES ('delete', old.id, old.title, old.artist, old.album); "
      'INSERT INTO tracks_fts(rowid, title, artist, album) '
      'VALUES (new.id, new.title, new.artist, new.album); '
      'END';

  /// Applies this migration on [db] (used by `AppDatabase.createFts` and
  /// available for manual re-runs after destructive FTS maintenance).
  static Future<void> create(AppDatabase db) async {
    await db.customStatement(ftsCreateSql);
    await db.customStatement(triggerInsertSql);
    await db.customStatement(triggerDeleteSql);
    await db.customStatement(triggerUpdateSql);
  }
}

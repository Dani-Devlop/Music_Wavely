import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/app_database.dart';

/// Schema migration version 1 → 2 (Stage 1.2).
///
/// Adds the Stage 1.2 tables (all plain CREATE TABLE IF NOT EXISTS — no FTS
/// involvement, so no table rebuilds are required):
/// - `http_cache`       — metadata-client response cache (B1/B10)
/// - `sync_outbox`      — local mutations pending push (B4)
/// - `blocked_words`    — parental word list (B8)
/// - `profiles_local`   — local parental profiles (B8)
/// - `parental_audit`   — append-only parental events (B8)
/// - `artist_follows`   — followed artists for discovery (B10)
abstract final class Migration0002 {
  /// Table names created by this migration (used by the migration runner).
  static const List<String> tableNames = <String>[
    'http_cache',
    'sync_outbox',
    'blocked_words',
    'profiles_local',
    'parental_audit',
    'artist_follows',
  ];

  /// Runs the migration. drift's generated `createTable` statements come
  /// from the updated [AppDatabase] schema; `m.createAll` would also be
  /// safe, but targeted creation keeps the upgrade scoped.
  static Future<void> run(Migrator m, AppDatabase db) async {
    await m.createTable(db.httpCache);
    await m.createTable(db.syncOutbox);
    await m.createTable(db.blockedWords);
    await m.createTable(db.profilesLocal);
    await m.createTable(db.parentalAudit);
    await m.createTable(db.artistFollows);
    await m.createIndex(db.idxSyncOutboxCreated);
  }
}

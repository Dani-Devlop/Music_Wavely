import 'package:drift/drift.dart';

/// Outbox of local mutations waiting to be pushed to Supabase (Stage 1.2).
///
/// Sync service contract:
/// - every local change enqueues a row here (insert/update/delete per table),
/// - [SyncService.pushChanges] drains rows oldest-first with retry
///   (max [AppConstants]-driven attempts), deleting rows on success,
/// - conflicts are resolved remotely via LWW (`updated_at`) or the
///   per-table rules in `conflict_resolver.dart`.
@DataClassName('SyncOutboxRow', companion: 'SyncOutboxCompanion')
@TableIndex(name: 'idx_sync_outbox_created', columns: {#createdAt})
class SyncOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Logical local table the mutation happened in (`plays`, `playlists`,
  /// `user_settings`, `artist_follows`, ...).
  TextColumn get tableName => text();

  /// Local primary key of the mutated row.
  TextColumn get rowKey => text();

  /// `insert` | `update` | `delete`.
  TextColumn get op => text();

  /// JSON payload of the changed row (delete ops carry key fields only).
  TextColumn get payload => text();

  /// Number of push attempts so far (reset on schema migration only).
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Row creation time — outbox is drained oldest-first.
  DateTimeColumn get createdAt => dateTime()();
}

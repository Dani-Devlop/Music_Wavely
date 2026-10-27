import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/tables/sync_outbox.dart';

part 'sync_outbox_dao.g.dart';

/// Outbox access for [SyncService]: enqueue, drain oldest-first, retry bookkeeping.
@DriftAccessor(tables: [SyncOutbox])
class SyncOutboxDao extends DatabaseAccessor<AppDatabase>
    with _$SyncOutboxDaoMixin {
  SyncOutboxDao(super.attachedDatabase);

  /// Maximum push attempts before an entry is parked (never silently
  /// dropped — [failed] surfaces them for the sync UI).
  static const int maxAttempts = 5;

  /// Enqueues one mutation.
  Future<int> enqueue({
    required String tableName,
    required String rowKey,
    required String op,
    required String payload,
  }) =>
      into(syncOutbox).insert(
        SyncOutboxCompanion.insert(
          tableName: tableName,
          rowKey: rowKey,
          op: op,
          payload: payload,
          createdAt: DateTime.now(),
        ),
      );

  /// Oldest [limit] pending entries, drained in order.
  Future<List<SyncOutboxRow>> pending({int limit = 50}) =>
      (select(syncOutbox)
            ..orderBy([(r) => OrderingTerm.asc(r.createdAt)])
            ..limit(limit))
          .get();

  /// Removes a successfully pushed entry.
  Future<int> remove(int id) =>
      (delete(syncOutbox)..where((r) => r.id.equals(id))).go();

  /// Bumps the attempt counter of a failed push.
  Future<void> bumpAttempts(int id, {required int attempts}) =>
      (update(syncOutbox)..where((r) => r.id.equals(id)))
          .write(SyncOutboxCompanion(attempts: Value(attempts)));

  /// Entries that exceeded [SyncOutboxDao.maxAttempts] (parked for the UI).
  Future<List<SyncOutboxRow>> failed() => (select(syncOutbox)
        ..where((r) => r.attempts.isBiggerOrEqualValue(maxAttempts)))
      .get();

  /// Pending count for the sync status UI.
  Future<int> count() async {
    final count = syncOutbox.id.count();
    final query = selectOnly(syncOutbox)..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }
}

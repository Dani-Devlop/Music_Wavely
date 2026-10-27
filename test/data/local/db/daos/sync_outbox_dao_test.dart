/// Authored, awaiting local run.
///
/// No Flutter/Dart SDK exists in the authoring sandbox, so this suite has
/// never been executed. It targets the real `SyncOutboxDao` API in `lib/`
/// and needs `dart run build_runner build` first (generates
/// `app_database.g.dart` and the DAO mixins).
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavely/data/local/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  /// Direct insert with an explicit createdAt so ordering tests stay
  /// deterministic (drift stores DateTimes with second granularity).
  Future<int> enqueueAt(
    DateTime createdAt, {
    String rowKey = 'k',
  }) {
    return db.into(db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            tableName: 'plays',
            rowKey: rowKey,
            op: 'insert',
            payload: '{"id": 1}',
            createdAt: createdAt,
          ),
        );
  }

  test('enqueue stores the mutation with a zero attempt counter', () async {
    final id = await db.syncOutboxDao.enqueue(
      tableName: 'plays',
      rowKey: '42',
      op: 'insert',
      payload: '{"id": 42}',
    );

    final row = await (db.select(db.syncOutbox)
          ..where((r) => r.id.equals(id)))
        .getSingle();
    expect(row.tableName, 'plays');
    expect(row.rowKey, '42');
    expect(row.op, 'insert');
    expect(row.payload, '{"id": 42}');
    expect(row.attempts, 0, reason: 'column default');
    expect(row.createdAt, isNotNull);
  });

  test('pending drains oldest-first (createdAt ascending)', () async {
    await enqueueAt(DateTime(2024, 1, 3), rowKey: 'third');
    await enqueueAt(DateTime(2024, 1, 1), rowKey: 'first');
    await enqueueAt(DateTime(2024, 1, 2), rowKey: 'second');

    final pending = await db.syncOutboxDao.pending();

    expect(pending.map((r) => r.rowKey), ['first', 'second', 'third']);
  });

  test('pending respects the limit', () async {
    await enqueueAt(DateTime(2024, 1, 1), rowKey: 'a');
    await enqueueAt(DateTime(2024, 1, 2), rowKey: 'b');
    await enqueueAt(DateTime(2024, 1, 3), rowKey: 'c');

    final pending = await db.syncOutboxDao.pending(limit: 2);

    expect(pending.map((r) => r.rowKey), ['a', 'b']);
  });

  test('remove deletes only the given entry and reports the count',
      () async {
    final id1 = await enqueueAt(DateTime(2024, 1, 1), rowKey: 'a');
    final id2 = await enqueueAt(DateTime(2024, 1, 2), rowKey: 'b');

    expect(await db.syncOutboxDao.remove(id2), 1);
    expect(await db.syncOutboxDao.remove(id2), 0);

    final remaining = await db.syncOutboxDao.pending();
    expect(remaining.map((r) => r.rowKey), ['a']);
    expect(await db.syncOutboxDao.count(), 1);
    expect(id1, isNot(id2));
  });

  test('count reflects the current outbox size', () async {
    expect(await db.syncOutboxDao.count(), 0);

    await db.syncOutboxDao.enqueue(
      tableName: 'plays',
      rowKey: '1',
      op: 'insert',
      payload: '{}',
    );
    await db.syncOutboxDao.enqueue(
      tableName: 'artist_follows',
      rowKey: 'aura',
      op: 'insert',
      payload: '{}',
    );

    expect(await db.syncOutboxDao.count(), 2);
  });

  test('bumpAttempts updates the counter; failed parks maxed entries',
      () async {
    final healthy = await enqueueAt(DateTime(2024, 1, 1), rowKey: 'ok');
    final doomed = await enqueueAt(DateTime(2024, 1, 2), rowKey: 'bad');

    await db.syncOutboxDao.bumpAttempts(healthy, attempts: 2);
    final healthyRow = await (db.select(db.syncOutbox)
          ..where((r) => r.id.equals(healthy)))
        .getSingle();
    expect(healthyRow.attempts, 2);
    expect(await db.syncOutboxDao.failed(), isEmpty);

    await db.syncOutboxDao.bumpAttempts(
      doomed,
      attempts: SyncOutboxDao.maxAttempts,
    );

    final failed = await db.syncOutboxDao.failed();
    expect(failed.map((r) => r.rowKey), ['bad']);
    expect(failed.single.attempts, SyncOutboxDao.maxAttempts);
    // Parked entries stay in the outbox (the UI surfaces them) — pending
    // still lists everything because it does not filter by attempts.
    expect((await db.syncOutboxDao.pending()).length, 2);
  });

  test('maxAttempts is 5', () {
    expect(SyncOutboxDao.maxAttempts, 5);
  });
}

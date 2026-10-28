// authored, awaiting local run.
//
// Tests for lib/data/sync/sync_service.dart against a hand-rolled fake
// lib/data/sync/sync_backend.dart (the documented seam) + a memory drift
// database + InMemorySettingsStore:
// - push: disabled backend, happy-path drain (oldest-first, rows removed),
//   batchSize paging, retry attempt bumping, park at maxAttempts=5,
//   thrown-exception containment.
// - pull: fingerprint identity match, (track, started-at-second) dedupe,
//   unknown-fingerprint skips, watermark advancement (epoch → stamp),
//   failure mapping, settings LWW through SettingsPullable.
// - lifecycle: connectivity regain triggers a round (StreamController<bool>),
//   the periodic pushInterval tick re-runs runOnce (fakeAsync), dispose
//   cancels the timer.
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/sync_outbox_dao.dart';
import 'package:wavely/data/sync/fingerprint.dart';
import 'package:wavely/data/sync/sync_backend.dart';
import 'package:wavely/data/sync/sync_service.dart';
import 'package:wavely/data/sync/sync_status.dart';
import 'package:wavely/domain/entities/entities.dart';

AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

/// Hand-rolled [SyncBackend] fake: records pushes, scripts pulls.
class _FakeBackend implements SyncBackend {
  final List<List<SyncOutboxRow>> pushes = <List<SyncOutboxRow>>[];
  int pullCount = 0;
  final List<DateTime> pullSinces = <DateTime>[];

  Result<void> Function(List<SyncOutboxRow> batch)? pushOverride;
  Object? pushThrows;
  Result<List<RemotePlay>> pullResult = Result<List<RemotePlay>>.success(
      const <RemotePlay>[]);
  Object? pullThrows;

  @override
  Future<Result<void>> push(List<SyncOutboxRow> batch) async {
    pushes.add(List<SyncOutboxRow>.of(batch));
    if (pushThrows != null) {
      throw pushThrows!;
    }
    final override = pushOverride;
    if (override != null) {
      return override(batch);
    }
    return const Result<void>.success(null);
  }

  @override
  Future<Result<List<RemotePlay>>> pull(DateTime since) async {
    pullCount++;
    pullSinces.add(since);
    if (pullThrows != null) {
      throw pullThrows!;
    }
    return pullResult;
  }
}

class _FakeSettingsBackend implements SyncBackend, SettingsPullable {
  _FakeSettingsBackend();

  int pullCount = 0;
  Result<List<RemotePlay>> pullResult = Result<List<RemotePlay>>.success(
      const <RemotePlay>[]);
  Result<RemoteSettingsSnapshot?> settingsResult =
      Result<RemoteSettingsSnapshot?>.success(null);

  @override
  Future<Result<void>> push(List<SyncOutboxRow> batch) async =>
      const Result<void>.success(null);

  @override
  Future<Result<List<RemotePlay>>> pull(DateTime since) async {
    pullCount++;
    return pullResult;
  }

  @override
  Future<Result<RemoteSettingsSnapshot?>> pullSettings() async =>
      settingsResult;
}

SyncOutboxCompanion _outboxRow(
  String rowKey, {
  required DateTime createdAt,
  String tableName = 'plays',
  String op = 'insert',
  String payload = '{"ok":true}',
}) =>
    SyncOutboxCompanion.insert(
      tableName: tableName,
      rowKey: rowKey,
      op: op,
      payload: payload,
      createdAt: createdAt,
    );

Future<Track> _seedTrack(
  AppDatabase db, {
  required String sourceTrackId,
  required String title,
  required String artist,
}) {
  return db.tracksDao.upsertBySource(
    TracksCompanion.insert(
      sourceId: 'local',
      sourceTrackId: sourceTrackId,
      title: title,
      artist: artist,
      durationMs: 1000,
      format: 'mp3',
      addedAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
  );
}

RemotePlay _remotePlay(
  String fingerprint,
  DateTime startedAt, {
  int listenedMs = 60000,
  bool completed = true,
}) =>
    RemotePlay(
      fingerprint: fingerprint,
      title: 'Remote Title',
      artist: 'Remote Artist',
      source: 'local',
      deviceId: 'remote-device',
      startedAt: startedAt,
      listenedMs: listenedMs,
      completed: completed,
    );

Future<void> _settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

SyncService _service(
  AppDatabase db,
  SettingsStore store,
  SyncBackend? backend, {
  Duration pushInterval = const Duration(minutes: 5),
}) =>
    SyncService(
      db: db,
      outboxDao: db.syncOutboxDao,
      playsDao: db.playsDao,
      tracksDao: db.tracksDao,
      settingsStore: store,
      backend: backend,
      pushInterval: pushInterval,
    );

void main() {
  group('push (outbox drain)', () {
    test('null backend parks the service in disabled and no-ops',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final service = _service(db, InMemorySettingsStore(), null);

      expect(service.status.status, SyncStatus.disabled);
      await service.pushChanges();
      final pull = await service.pullChanges();

      expect(pull.inserted, 0);
      expect(pull.duplicates, 0);
      expect(pull.skipped, 0);
      expect(service.status.status, SyncStatus.disabled);
    });

    test('happy path: rows drained oldest-first, removed on success, '
        'status returns to idle', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final backend = _FakeBackend();
      final base = DateTime(2026, 6, 1, 12);
      await db.into(db.syncOutbox).insert(_outboxRow('row-1',
          createdAt: base));
      await db.into(db.syncOutbox).insert(_outboxRow('row-2',
          createdAt: base.add(const Duration(seconds: 1))));
      final events = <SyncStatusView>[];
      final service = _service(db, InMemorySettingsStore(), backend);
      addTearDown(service.dispose);
      service.statusStream.listen(events.add);

      await service.pushChanges();

      expect(backend.pushes, hasLength(1));
      expect(
        [for (final row in backend.pushes.single) row.rowKey],
        <String>['row-1', 'row-2'],
      );
      expect(await db.syncOutboxDao.count(), 0);
      expect(service.status.status, SyncStatus.idle);
      // syncing → idle on the broadcast stream.
      expect(
        [for (final event in events) event.status],
        containsAllInOrder(<SyncStatus>[SyncStatus.syncing, SyncStatus.idle]),
      );
    });

    test('drains in batches of SyncService.batchSize', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final backend = _FakeBackend();
      final base = DateTime(2026, 6, 1, 12);
      for (var i = 0; i < SyncService.batchSize + 5; i++) {
        await db.into(db.syncOutbox).insert(_outboxRow('row-$i',
            createdAt: base.add(Duration(seconds: i))));
      }
      final service = _service(db, InMemorySettingsStore(), backend);
      addTearDown(service.dispose);

      await service.pushChanges();

      expect(backend.pushes, hasLength(2));
      expect(backend.pushes[0], hasLength(SyncService.batchSize));
      expect(backend.pushes[1], hasLength(5));
      expect(await db.syncOutboxDao.count(), 0);
    });

    test('a failed round bumps every row attempt once and reports error',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final backend = _FakeBackend()
        ..pushOverride = (batch) => Result<void>.err(
            const Failure.network(message: 'transport down'));
      final base = DateTime(2026, 6, 1, 12);
      await db.into(db.syncOutbox).insert(_outboxRow('row-1',
          createdAt: base));
      final service = _service(db, InMemorySettingsStore(), backend);
      addTearDown(service.dispose);

      await service.pushChanges();

      expect(backend.pushes, hasLength(1)); // one round, then stop
      final rows = await db.syncOutboxDao.pending();
      expect(rows.single.attempts, 1);
      expect(service.status.status, SyncStatus.error);
      expect(service.status.lastError, 'transport down');
    });

    test('rows park after SyncOutboxDao.maxAttempts (5) and are skipped '
        'forever after', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final backend = _FakeBackend()
        ..pushOverride = (batch) =>
            Result<void>.err(const Failure.network(message: 'flaky'));
      await db.into(db.syncOutbox).insert(_outboxRow('row-1',
          createdAt: DateTime(2026, 6, 1, 12)));
      final service = _service(db, InMemorySettingsStore(), backend);
      addTearDown(service.dispose);

      for (var round = 0; round < SyncOutboxDao.maxAttempts; round++) {
        await service.pushChanges();
      }

      final failed = await db.syncOutboxDao.failed();
      expect(failed, hasLength(1));
      expect(failed.single.attempts, SyncOutboxDao.maxAttempts);

      // The 6th round sees only parked rows → no backend call, idle status.
      backend.pushOverride = (batch) => const Result<void>.success(null);
      await service.pushChanges();
      expect(backend.pushes, hasLength(SyncOutboxDao.maxAttempts));
      expect(service.status.status, SyncStatus.idle);
      expect(service.status.lastError, isNull);
      // Parked rows are surfaced (never silently dropped) but not pushed.
      expect(await db.syncOutboxDao.failed(), hasLength(1));
    });

    test('a backend exception is contained as SyncStatus.error',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final backend = _FakeBackend()..pushThrows = StateError('boom');
      await db.into(db.syncOutbox).insert(_outboxRow('row-1',
          createdAt: DateTime(2026, 6, 1, 12)));
      final service = _service(db, InMemorySettingsStore(), backend);
      addTearDown(service.dispose);

      await service.pushChanges();

      expect(service.status.status, SyncStatus.error);
      expect(service.status.lastError, contains('boom'));
    });
  });

  group('pull (remote plays)', () {
    test('fingerprint match inserts; same-second duplicate and unknown '
        'fingerprint are dropped', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final local = await _seedTrack(db,
          sourceTrackId: 'st-1', title: 'Song One', artist: 'Artist One');
      final fingerprint = playFingerprint(local);
      final other = await _seedTrack(db,
          sourceTrackId: 'st-2', title: 'Song Two', artist: 'Artist Two');
      // A pre-existing local play at T3 — a remote play at the same second
      // must count as a duplicate.
      await db.playsDao.insertPlay(
        PlaysCompanion.insert(
          trackId: local.id!,
          startedAt: DateTime(2026, 3, 1, 9),
          listenedMs: 1000,
          source: 'local',
          deviceId: 'local-device',
        ),
      );

      final backend = _FakeBackend()
        ..pullResult = Result<List<RemotePlay>>.success(<RemotePlay>[
          _remotePlay(fingerprint, DateTime(2026, 3, 1, 10)), // insert
          _remotePlay(
              fingerprint, DateTime(2026, 3, 1, 10, 0, 0, 200)), // dup
          _remotePlay(playFingerprint(other), DateTime(2026, 3, 2, 10)),
          _remotePlay('deadbeef' * 5, DateTime(2026, 3, 3, 10)), // unknown
          _remotePlay(fingerprint, DateTime(2026, 3, 1, 9)), // local dup
        ]);
      final store = InMemorySettingsStore();
      final service = _service(db, store, backend);
      addTearDown(service.dispose);

      final result = await service.pullChanges();

      expect(result.inserted, 2);
      expect(result.duplicates, 2);
      expect(result.skipped, 1);
      expect(service.status.status, SyncStatus.idle);

      final plays = await db.playsDao.playsForTrack(local.id!);
      expect(plays, hasLength(2)); // 1 pre-existing local + 1 pulled
      final remoteRows = await db.playsDao.playsForTrack(other.id!);
      expect(remoteRows, hasLength(1));
      expect(remoteRows.single.listenedMs, 60000);
      expect(remoteRows.single.completed, isTrue);
      expect(remoteRows.single.deviceId, 'remote-device');
    });

    test('first pull passes the epoch watermark; the next pull passes the '
        'persisted stamp', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final backend = _FakeBackend();
      final store = InMemorySettingsStore();
      final service = _service(db, store, backend);
      addTearDown(service.dispose);

      await service.pullChanges();
      expect(backend.pullSinces.single,
          DateTime.fromMillisecondsSinceEpoch(0));
      expect(await store.read<String>(SyncService.lastPulledAtKey),
          isNotNull);

      await service.pullChanges();
      expect(backend.pullCount, 2);
      expect(backend.pullSinces.last.isAfter(DateTime(2020)), isTrue);
    });

    test('a failed pull does not advance the watermark', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final backend = _FakeBackend()
        ..pullResult = Result<List<RemotePlay>>.err(
            const Failure.network(message: 'pull failed'));
      final store = InMemorySettingsStore();
      final service = _service(db, store, backend);
      addTearDown(service.dispose);

      final result = await service.pullChanges();

      expect(result.inserted, 0);
      expect(service.status.status, SyncStatus.error);
      expect(service.status.lastError, 'pull failed');
      expect(await store.read<String>(SyncService.lastPulledAtKey), isNull);
    });

    test('a thrown pull exception is contained and reported', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final backend = _FakeBackend()..pullThrows = StateError('socket died');
      final service = _service(db, InMemorySettingsStore(), backend);
      addTearDown(service.dispose);

      final result = await service.pullChanges();

      expect(result.inserted, 0);
      expect(service.status.status, SyncStatus.error);
      expect(service.status.lastError, contains('socket died'));
    });
  });

  group('settings LWW (SettingsPullable)', () {
    test('newer remote snapshot wins and is persisted under '
        'SyncService.localSettingsKey', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final store = InMemorySettingsStore();
      await store.write(
        SyncService.localSettingsKey,
        jsonEncode(<String, dynamic>{
          'payload': <String, dynamic>{'theme': 'local'},
          'updatedAt': '2026-01-01T00:00:00.000',
        }),
      );
      final backend = _FakeSettingsBackend()
        ..settingsResult = Result<RemoteSettingsSnapshot?>.success(
          RemoteSettingsSnapshot(
            payload: <String, dynamic>{'theme': 'remote'},
            updatedAt: DateTime(2026, 6, 1),
          ),
        );
      final service = _service(db, store, backend);
      addTearDown(service.dispose);

      await service.pullChanges();

      final raw = await store.read<String>(SyncService.localSettingsKey);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['payload'], <String, dynamic>{'theme': 'remote'});
      expect(decoded['updatedAt'], '2026-06-01T00:00:00.000');
    });

    test('newer local snapshot survives (LWW keeps the local payload)',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final store = InMemorySettingsStore();
      await store.write(
        SyncService.localSettingsKey,
        jsonEncode(<String, dynamic>{
          'payload': <String, dynamic>{'theme': 'local-newer'},
          'updatedAt': '2027-01-01T00:00:00.000',
        }),
      );
      final backend = _FakeSettingsBackend()
        ..settingsResult = Result<RemoteSettingsSnapshot?>.success(
          RemoteSettingsSnapshot(
            payload: <String, dynamic>{'theme': 'remote-older'},
            updatedAt: DateTime(2026, 6, 1),
          ),
        );
      final service = _service(db, store, backend);
      addTearDown(service.dispose);

      await service.pullChanges();

      final raw = await store.read<String>(SyncService.localSettingsKey);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['payload'], <String, dynamic>{'theme': 'local-newer'});
    });

    test('a plain SyncBackend (not SettingsPullable) never writes the '
        'settings key', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final store = InMemorySettingsStore();
      final service = _service(db, store, _FakeBackend());
      addTearDown(service.dispose);

      await service.pullChanges();

      expect(await store.read<String>(SyncService.localSettingsKey), isNull);
    });
  });

  group('lifecycle', () {
    test('connectivity regain triggers a full round; losses do not',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final backend = _FakeBackend();
      final connectivity = StreamController<bool>();
      addTearDown(connectivity.close);
      final service = _service(db, InMemorySettingsStore(), backend);
      addTearDown(service.dispose);

      await service.start(connectivityChanges: connectivity.stream);
      await _settle();
      expect(backend.pullCount, 1); // initial runOnce

      connectivity.add(false);
      await _settle();
      expect(backend.pullCount, 1);

      connectivity.add(true);
      await _settle();
      expect(backend.pullCount, 2);
    });

    test('the periodic pushInterval tick re-runs runOnce', () {
      fakeAsync((async) {
        final db = _memoryDb();
        final backend = _FakeBackend();
        final service = _service(
          db,
          InMemorySettingsStore(),
          backend,
          pushInterval: const Duration(minutes: 5),
        );

        unawaited(service.start());
        async.elapse(const Duration(milliseconds: 1)); // drain initial round
        expect(backend.pullCount, 1);

        async.elapse(const Duration(minutes: 5));
        expect(backend.pullCount, 2);

        async.elapse(const Duration(minutes: 5));
        expect(backend.pullCount, 3);

        service.dispose();
        async.elapse(const Duration(minutes: 30));
        expect(backend.pullCount, 3); // timer canceled by dispose
      });
    });

    test('runOnce is the tick: push then pull in one call', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final backend = _FakeBackend();
      await db.into(db.syncOutbox).insert(_outboxRow('row-1',
          createdAt: DateTime(2026, 6, 1, 12)));
      final service = _service(db, InMemorySettingsStore(), backend);
      addTearDown(service.dispose);

      await service.runOnce();

      expect(backend.pushes, hasLength(1));
      expect(backend.pullCount, 1);
      expect(await db.syncOutboxDao.count(), 0);
      expect(service.status.status, SyncStatus.idle);
    });
  });
}

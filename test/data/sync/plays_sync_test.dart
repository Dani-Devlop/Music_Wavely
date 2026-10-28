// authored, awaiting local run.
//
// Tests for lib/data/sync/plays_sync.dart (the outgoing play queue) plus the
// pure SupabaseSyncBackend payload mappers it rides on:
// - PlaysSync.enqueuePlay → outbox row ('plays' / 'insert' /
//   '<fingerprint>:<startedAtIso>' / snake_case payload, NO user id).
// - PlaysSyncOutboxHook.record → records via PlayRecorder then copies the
//   newest plays row into the outbox; un-persisted tracks record nothing.
// - SupabaseSyncBackend.playToPayload / playPayloadFromRow (fingerprint
//   forced from the row key) / fingerprintFromRowKey /
//   dailyStatsEntriesFromPayload / remoteTableFor.
// - RemotePlay.fromMap/toMap roundtrip.
//
// NOTE on the task hint: "dedupe skip on pull, orphan remote rows skipped"
// live in SyncService._applyRemotePlays (sync_service_test.dart covers them
// with PullResult.inserted/duplicates/skipped) — PlaysSync itself only
// enqueues.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/plays_dao.dart';
import 'package:wavely/data/local/db/daos/sync_outbox_dao.dart';
import 'package:wavely/data/repositories/play_recorder.dart';
import 'package:wavely/data/sync/fingerprint.dart';
import 'package:wavely/data/sync/plays_sync.dart';
import 'package:wavely/data/sync/supabase_sync_backend.dart';
import 'package:wavely/data/sync/sync_backend.dart';
import 'package:wavely/domain/entities/entities.dart';

AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

Track _unpersistedTrack() => Track(
      sourceId: 'local',
      sourceTrackId: 'no-row',
      title: 'Ghost Song',
      artist: 'Ghost Artist',
      durationMs: 1000,
      format: 'mp3',
      addedAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Future<Track> _seedTrack(AppDatabase db) {
  return db.tracksDao.upsertBySource(
    TracksCompanion.insert(
      sourceId: 'local',
      sourceTrackId: 'st-1',
      title: 'Real Song',
      artist: 'Real Artist',
      album: const Value('Real Album'),
      durationMs: 1000,
      format: 'mp3',
      addedAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
  );
}

void main() {
  group('PlaysSync.enqueuePlay (append-only push mapping)', () {
    test('enqueues one plays outbox row with the canonical payload',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final track = await _seedTrack(db);
      final playsSync = PlaysSync(outboxDao: db.syncOutboxDao);

      final startedAt = DateTime.utc(2026, 6, 15, 12, 30, 15);
      await playsSync.enqueuePlay(
        PlayRow(
          id: 7,
          trackId: track.id!,
          startedAt: startedAt,
          listenedMs: 123000,
          completed: true,
          source: 'local',
          deviceId: 'device-1',
        ),
        track,
      );

      final rows = await db.syncOutboxDao.pending();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.outboxTable, 'plays');
      expect(row.op, 'insert');
      final fingerprint = playFingerprint(track);
      expect(row.rowKey, '$fingerprint:${startedAt.toIso8601String()}');
      expect(row.attempts, 0);

      final payload = jsonDecode(row.payload) as Map<String, dynamic>;
      expect(payload, SupabaseSyncBackend.playToPayload(
        fingerprint: fingerprint,
        title: track.title,
        artist: track.artist,
        album: track.album,
        source: 'local',
        deviceId: 'device-1',
        startedAt: startedAt,
        listenedMs: 123000,
        completed: true,
      ));
      // Remote column names, no user id (attribution is remote RLS).
      expect(payload.keys, containsAll(<String>[
        'fingerprint', 'title', 'artist', 'album', 'source', 'device_id',
        'started_at', 'listened_ms', 'completed',
      ]));
      expect(payload.containsKey('user_id'), isFalse);
    });

    test('two sessions of the same track produce two rows (append-only), '
        'distinguished by rowKey', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final track = await _seedTrack(db);
      final playsSync = PlaysSync(outboxDao: db.syncOutboxDao);

      await playsSync.enqueuePlay(
        PlayRow(
          id: 1,
          trackId: track.id!,
          startedAt: DateTime.utc(2026, 6, 15, 8),
          listenedMs: 60000,
          completed: false,
          source: 'local',
          deviceId: 'device-1',
        ),
        track,
      );
      await playsSync.enqueuePlay(
        PlayRow(
          id: 2,
          trackId: track.id!,
          startedAt: DateTime.utc(2026, 6, 15, 9),
          listenedMs: 60000,
          completed: true,
          source: 'local',
          deviceId: 'device-1',
        ),
        track,
      );

      final rows = await db.syncOutboxDao.pending();
      expect(rows, hasLength(2));
      expect(
        {for (final row in rows) row.rowKey},
        hasLength(2), // distinct started_at stamps
      );
    });
  });

  group('PlaysSyncOutboxHook.record', () {
    test('records the play via PlayRecorder and copies the newest plays row '
        'into the outbox', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final track = await _seedTrack(db);
      final hook = PlaysSyncOutboxHook(
        recorder: PlayRecorder(db.playsDao, deviceId: 'device-9'),
        playsSync: PlaysSync(outboxDao: db.syncOutboxDao),
        playsDao: db.playsDao,
      );

      await hook.record(track);

      final plays = await db.playsDao.playsForTrack(track.id!);
      expect(plays, hasLength(1));
      expect(plays.single.deviceId, 'device-9');
      expect(plays.single.source, 'local');

      final rows = await db.syncOutboxDao.pending();
      expect(rows, hasLength(1));
      final payload = jsonDecode(rows.single.payload) as Map<String, dynamic>;
      expect(payload['device_id'], 'device-9');
      expect(payload['started_at'], plays.single.startedAt.toIso8601String());
    });

    test('a track without a database id records nothing (no foreign key)',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final hook = PlaysSyncOutboxHook(
        recorder: PlayRecorder(db.playsDao, deviceId: 'device-9'),
        playsSync: PlaysSync(outboxDao: db.syncOutboxDao),
        playsDao: db.playsDao,
      );

      await hook.record(_unpersistedTrack());

      expect(await db.syncOutboxDao.count(), 0);
      // The recorder itself skips id-less tracks — nothing was written.
      final count = await db
          .select(db.plays)
          .get();
      expect(count, isEmpty);
    });
  });

  group('SupabaseSyncBackend pure mappers', () {
    test('playToPayload produces the canonical snake_case row', () {
      final startedAt = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final payload = SupabaseSyncBackend.playToPayload(
        fingerprint: 'f' * 40,
        title: 'T',
        artist: 'A',
        album: null,
        source: 'local',
        deviceId: 'd1',
        startedAt: startedAt,
        listenedMs: 42,
        completed: false,
      );

      expect(payload, <String, dynamic>{
        'fingerprint': 'f' * 40,
        'title': 'T',
        'artist': 'A',
        'album': null,
        'source': 'local',
        'device_id': 'd1',
        'started_at': startedAt.toIso8601String(),
        'listened_ms': 42,
        'completed': false,
      });
    });

    test('fingerprintFromRowKey accepts only sha1-shaped prefixes',
        () {
      final sha1 = 'a' * 40;
      expect(SupabaseSyncBackend.fingerprintFromRowKey('$sha1:2026-01-01'),
          sha1);
      expect(
          SupabaseSyncBackend.fingerprintFromRowKey('short:2026'), isNull);
      expect(
          SupabaseSyncBackend.fingerprintFromRowKey(
              '${'A' * 40}:2026'), // uppercase → not a sha1 hex digest
          isNull);
      expect(SupabaseSyncBackend.fingerprintFromRowKey('nocolon'), isNull);
    });

    test('playPayloadFromRow forces the row-key fingerprint over a '
        'corrupted payload', () {
      final sha1 = 'b' * 40;
      final row = SyncOutboxRow(
        id: 1,
        outboxTable: 'plays',
        rowKey: '$sha1:2026-06-01T00:00:00.000Z',
        op: 'insert',
        payload: jsonEncode(<String, dynamic>{
          'fingerprint': 'corrupted',
          'title': 'T',
          'device_id': 'd',
          'started_at': '2026-06-01T00:00:00.000Z',
          'listened_ms': 1,
          'completed': true,
          'source': 'local',
          'artist': 'A',
          'album': null,
        }),
        attempts: 0,
        createdAt: DateTime(2026),
      );

      final payload = SupabaseSyncBackend.playPayloadFromRow(row);
      expect(payload['fingerprint'], sha1); // forced back from the row key
    });

    test('dailyStatsEntriesFromPayload expands a batch into one row per '
        'entry', () {
      const payload = '{"day":"2026-06-15","entries":['
          '{"fingerprint":"aaa","plays":3,"listened_ms":150000},'
          '{"fingerprint":"bbb","plays":1,"listened_ms":30000}]}';

      final entries =
          SupabaseSyncBackend.dailyStatsEntriesFromPayload(payload);

      expect(entries, hasLength(2));
      expect(entries[0], <String, dynamic>{
        'day': '2026-06-15',
        'fingerprint': 'aaa',
        'plays': 3,
        'listened_ms': 150000,
      });
      expect(entries[1]['fingerprint'], 'bbb');
    });

    test('remoteTableFor maps the four synced tables and null otherwise',
        () {
      expect(SupabaseSyncBackend.remoteTableFor('plays'), 'plays');
      expect(SupabaseSyncBackend.remoteTableFor('artist_follows'),
          'artist_follows');
      expect(SupabaseSyncBackend.remoteTableFor('user_settings'),
          'user_settings');
      expect(SupabaseSyncBackend.remoteTableFor('track_stats_daily'),
          'track_stats_daily');
      expect(SupabaseSyncBackend.remoteTableFor('playlists'), isNull);
      expect(SupabaseSyncBackend.remoteTableFor('unknown'), isNull);
    });
  });

  group('RemotePlay wire mapping', () {
    test('fromMap decodes the snake_case remote row (UTC started_at)',
        () {
      final play = RemotePlay.fromMap(<String, dynamic>{
        'fingerprint': 'f' * 40,
        'title': 'T',
        'artist': 'A',
        'album': 'X',
        'source': 'local',
        'device_id': 'd2',
        'started_at': '2026-03-04T05:06:07.000Z',
        'listened_ms': 90000,
        'completed': true,
      });

      expect(play.fingerprint, 'f' * 40);
      expect(play.title, 'T');
      expect(play.artist, 'A');
      expect(play.album, 'X');
      expect(play.source, 'local');
      expect(play.deviceId, 'd2');
      expect(play.startedAt, DateTime.utc(2026, 3, 4, 5, 6, 7));
      expect(play.listenedMs, 90000);
      expect(play.completed, isTrue);
    });

    test('toMap/fromMap roundtrip is lossless', () {
      final startedAt = DateTime.utc(2026, 6, 1, 10);
      final original = RemotePlay(
        fingerprint: 'abc123',
        title: 'Song',
        artist: 'Artist',
        album: null,
        source: 'local',
        deviceId: 'device',
        startedAt: startedAt,
        listenedMs: 12000,
        completed: false,
      );

      final decoded = RemotePlay.fromMap(original.toMap());

      expect(decoded.fingerprint, original.fingerprint);
      expect(decoded.title, original.title);
      expect(decoded.artist, original.artist);
      expect(decoded.album, original.album);
      expect(decoded.source, original.source);
      expect(decoded.deviceId, original.deviceId);
      expect(decoded.startedAt, original.startedAt);
      expect(decoded.listenedMs, original.listenedMs);
      expect(decoded.completed, original.completed);
    });
  });
}

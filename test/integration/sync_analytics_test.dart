// Stage 5 cross-feature regression — Scenario 3: Sync Engine × Analytics.
//
// Full offline→online round trip over one shared Drift database:
//
//   PlayRecorder + PlaysSync (PlaysSyncOutboxHook)
//     → session recorded at track start (listenedMs: 0 snapshot)
//       → user skips halfway → finalizeSession writes the REAL numbers and
//         refreshes the pending outbox payload (Stage 5 fix)
//         → SyncService push fails while OFFLINE (attempts bumped, row kept)
//           → connectivity returns → push succeeds with the CORRECT
//             listened_ms in the remote payload
//             → AnalyticsRepository aggregates the same numbers locally,
//               including a pulled play from another device.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/sync_outbox_dao.dart';
import 'package:wavely/data/local/db/mappers/track_mapper.dart';
import 'package:wavely/data/repositories/play_recorder.dart';
import 'package:wavely/data/sync/fingerprint.dart';
import 'package:wavely/data/sync/plays_sync.dart';
import 'package:wavely/data/sync/sync_backend.dart';
import 'package:wavely/data/sync/sync_service.dart';
import 'package:wavely/data/sync/sync_status.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/analytics/data/analytics_repository.dart';

/// Hand-rolled [SyncBackend] whose behaviour the test flips at runtime
/// (offline = failing push, online = succeeding push).
class _ScriptedBackend implements SyncBackend {
  final List<List<SyncOutboxRow>> pushes = <List<SyncOutboxRow>>[];
  final List<String> pushedPayloads = <String>[];
  bool pushSucceeds = false;
  Result<List<RemotePlay>> pullResult = Result<List<RemotePlay>>.success(
    const <RemotePlay>[],
  );

  @override
  Future<Result<void>> push(List<SyncOutboxRow> batch) async {
    pushes.add(List<SyncOutboxRow>.of(batch));
    for (final SyncOutboxRow row in batch) {
      pushedPayloads.add(row.payload);
    }
    if (!pushSucceeds) {
      return const Result<void>.err(
        Failure.network(message: 'offline (scripted)'),
      );
    }
    return const Result<void>.success(null);
  }

  @override
  Future<Result<List<RemotePlay>>> pull(DateTime since) async => pullResult;
}

const Duration _kDuration = Duration(minutes: 3);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _ScriptedBackend backend;
  late SyncService sync;
  late AnalyticsRepository analytics;
  late PlaysSyncOutboxHook hook;
  late Track track;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    backend = _ScriptedBackend();
    final InMemorySettingsStore store = InMemorySettingsStore();
    sync = SyncService(
      db: db,
      outboxDao: db.syncOutboxDao,
      playsDao: db.playsDao,
      tracksDao: db.tracksDao,
      settingsStore: store,
      backend: backend,
    );
    analytics = AnalyticsRepository(
      db: db,
      tracksDao: db.tracksDao,
      playsDao: db.playsDao,
      outboxDao: db.syncOutboxDao,
    );
    hook = PlaysSyncOutboxHook(
      recorder: PlayRecorder(db.playsDao, deviceId: 'test-device'),
      playsSync: PlaysSync(outboxDao: db.syncOutboxDao),
      playsDao: db.playsDao,
    );

    final DateTime now = DateTime.utc(2024, 5, 1, 10);
    final Track seeded = Track(
      sourceId: 'local',
      sourceTrackId: 'session-1',
      title: 'Halfway Skipped',
      artist: 'Regression Band',
      album: 'Stage 5',
      genre: 'Rock',
      durationMs: _kDuration.inMilliseconds,
      format: 'mp3',
      addedAt: now,
      updatedAt: now,
    );
    final int id =
        await db.tracksDao.insertTrack(TrackMapper.toCompanion(seeded));
    track = seeded.copyWith(id: id);
  });

  tearDown(() async {
    sync.dispose();
    await db.close();
  });

  test('offline skip → online push carries the real listened_ms; analytics '
      'aggregate matches', () async {
    // ── Offline: start the session, skip halfway ─────────────────────────
    await hook.record(track);
    expect(await db.syncOutboxDao.count(), 1);

    // Start-of-session snapshot is a zero (the documented recorder contract).
    final List<PlayRow> atStart = await db.playsDao.playsForTrack(track.id!);
    expect(atStart.single.listenedMs, 0);
    expect(atStart.single.completed, isFalse);

    // The user skips halfway: the playback engine finalizes the session.
    final int halfway = _kDuration.inMilliseconds ~/ 2; // 90 000 ms
    final bool finalized = await hook.finalizeSession(
      track: track,
      listenedMs: halfway,
      completed: false,
    );
    expect(finalized, isTrue,
        reason: 'the Stage 5 session-finalization fix must update the row');

    final PlayRow session = (await db.playsDao.playsForTrack(track.id!)).single;
    expect(session.listenedMs, halfway);
    expect(session.completed, isFalse);

    // The pending outbox payload was refreshed too — pushing the start
    // snapshot (0) would lose the listening time on the remote side.
    final List<SyncOutboxRow> pending = await db.syncOutboxDao.pending();
    expect(pending, hasLength(1));
    final Map<String, dynamic> stagedPayload =
        jsonDecode(pending.single.payload) as Map<String, dynamic>;
    expect(stagedPayload['listened_ms'], halfway);
    expect(stagedPayload['completed'], isFalse);

    // ── Push while offline: transport fails, row is kept for retry ───────
    await sync.pushChanges();
    expect(sync.status.status, SyncStatus.error);
    expect(await db.syncOutboxDao.count(), 1,
        reason: 'failed push must keep the row');
    final List<SyncOutboxRow> retried = await db.syncOutboxDao.pending();
    expect(retried.single.attempts, 1);

    // ── Connectivity returns: push succeeds with the correct numbers ────
    backend.pushSucceeds = true;
    await sync.pushChanges();
    expect(sync.status.status, SyncStatus.idle);
    expect(await db.syncOutboxDao.count(), 0);

    expect(backend.pushes, hasLength(1));
    final Map<String, dynamic> pushed =
        jsonDecode(backend.pushedPayloads.single) as Map<String, dynamic>;
    expect(pushed['listened_ms'], halfway,
        reason: 'Supabase must receive the REAL listened time, not the '
            'start-of-session zero');
    expect(pushed['completed'], isFalse);
    expect(pushed['fingerprint'], playFingerprint(track));
    expect(pushed['device_id'], 'test-device');

    // ── Local analytics aggregate the same session ───────────────────────
    final DateTime now = DateTime.utc(2024, 5, 1, 12);
    expect(
      await analytics.getTotalListeningTime(AnalyticsPeriod.lifetime, now: now),
      halfway,
    );
    final List<TopEntry> top = await analytics.getTopTracks(
      AnalyticsPeriod.lifetime,
      now: now,
    );
    expect(top, hasLength(1));
    expect(top.single.track.id, track.id);
    expect(top.single.plays, 1);
    expect(top.single.listenedMs, halfway);

    // Skipped halfway (completed = false) counts as a skip…
    expect(
      await analytics.getSkipRate(AnalyticsPeriod.lifetime, now: now),
      1.0,
    );
  });

  test('mixed sessions: skip + completion aggregate; remote pull joins the '
      'aggregate', () async {
    // Session 1: halfway skip.
    await hook.record(track);
    await hook.finalizeSession(
      track: track,
      listenedMs: _kDuration.inMilliseconds ~/ 2,
      completed: false,
    );

    // Session 2: plays to completion. Real sessions are minutes apart; the
    // pause guarantees distinct started-at seconds (drift stores datetimes
    // at second precision, so same-second rows would order ambiguously).
    final Track laterTrack = track.copyWith(
      updatedAt: track.updatedAt.add(const Duration(minutes: 1)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await hook.record(laterTrack);
    await hook.finalizeSession(
      track: laterTrack,
      listenedMs: _kDuration.inMilliseconds,
      completed: true,
    );

    final DateTime now = DateTime.utc(2024, 5, 1, 12);
    expect(
      await analytics.getTotalListeningTime(AnalyticsPeriod.lifetime, now: now),
      _kDuration.inMilliseconds ~/ 2 + _kDuration.inMilliseconds,
    );
    final List<TopEntry> top = await analytics.getTopTracks(
      AnalyticsPeriod.lifetime,
      now: now,
    );
    expect(top.single.plays, 2);
    expect(
      top.single.listenedMs,
      _kDuration.inMilliseconds ~/ 2 + _kDuration.inMilliseconds,
    );
    expect(
      await analytics.getSkipRate(AnalyticsPeriod.lifetime, now: now),
      0.5,
      reason: 'one of two sessions was a skip',
    );

    // ── Another device pushed a play of the same track; go online and pull.
    final DateTime remoteStart = DateTime.utc(2024, 5, 1, 9);
    backend.pullResult = Result<List<RemotePlay>>.success(<RemotePlay>[
      RemotePlay(
        fingerprint: playFingerprint(track),
        title: track.title,
        artist: track.artist,
        album: track.album,
        source: track.sourceId,
        deviceId: 'phone',
        startedAt: remoteStart,
        listenedMs: 60000,
        completed: false,
      ),
    ]);
    final PullResult pulled = await sync.pullChanges();
    expect(pulled.inserted, 1);
    expect(pulled.skipped, 0);

    // The remote play joined the local aggregate (fingerprint identity).
    expect(
      await analytics.getTotalListeningTime(AnalyticsPeriod.lifetime, now: now),
      _kDuration.inMilliseconds ~/ 2 + _kDuration.inMilliseconds + 60000,
    );
    final List<TopEntry> topAfterPull = await analytics.getTopTracks(
      AnalyticsPeriod.lifetime,
      now: now,
    );
    expect(topAfterPull.single.plays, 3);
    expect(
      await analytics.getSkipRate(AnalyticsPeriod.lifetime, now: now),
      closeTo(2 / 3, 1e-9),
    );
  });

  test('finalizeSession without a recorded session is a safe no-op', () async {
    final bool changed = await hook.finalizeSession(
      track: track,
      listenedMs: 1000,
      completed: true,
    );
    expect(changed, isFalse);
    expect(await db.playsDao.playsForTrack(track.id!), isEmpty);
    expect(await db.syncOutboxDao.count(), 0);
  });

  test('push failure after finalize keeps the refreshed payload for retry',
      () async {
    await hook.record(track);
    await hook.finalizeSession(
      track: track,
      listenedMs: 45000,
      completed: false,
    );

    // Five consecutive offline rounds park the row (never silently lost).
    for (var i = 0; i < SyncOutboxDao.maxAttempts; i++) {
      await sync.pushChanges();
    }
    final List<SyncOutboxRow> parked = await db.syncOutboxDao.failed();
    expect(parked, hasLength(1));
    expect(
      (jsonDecode(parked.single.payload) as Map<String, dynamic>)['listened_ms'],
      45000,
      reason: 'parked rows keep the FINAL session numbers, ready for the '
          'sync UI to surface',
    );
  });
}

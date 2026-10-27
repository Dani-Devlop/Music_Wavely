// ORCHESTRATOR WIRING — how the outgoing plays queue hooks into playback:
//
// The hook wraps the existing PlayRecorder (it records first, then copies the
// freshly written `plays` row into the sync outbox). In
// `lib/app/providers.dart`, replace the `onTrackStarted` hook of
// `queueManagerProvider` inside `buildOverrides` with:
//
//   queueManagerProvider.overrideWith(
//     (ref) => QueueManager(
//       engine: ref.watch(playbackEngineProvider),
//       store: ref.watch(settingsStoreProvider),
//       trackSource: ref.watch(queueTrackSourceProvider),
//       onTrackStarted: (track) => unawaited(
//         ref.read(playsSyncOutboxHookProvider).record(track),
//       ),
//     ),
//   ),
//
// (`playsSyncOutboxHookProvider.record` calls `playRecorderProvider` first,
// so the existing play-history behavior is preserved; nothing else changes.)
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/data/local/db/daos/plays_dao.dart';
import 'package:wavely/data/local/db/daos/sync_outbox_dao.dart';
import 'package:wavely/data/repositories/play_recorder.dart';
import 'package:wavely/data/sync/fingerprint.dart';
import 'package:wavely/data/sync/supabase_sync_backend.dart';
import 'package:wavely/domain/entities/entities.dart';

/// Outgoing queue for played tracks: copies every locally recorded play into
/// the sync outbox so [SyncService] can push it to the remote `plays` table.
///
/// The outbox row:
/// - tableName: `'plays'` (mapped to the remote table by
///   `SupabaseSyncBackend.remoteTableFor`),
/// - rowKey: `'<fingerprint>:<startedAtIso>'` (the dedupe identity on the
///   remote side is `(user_id, fingerprint, started_at)`; the fingerprint is
///   forced back into the payload at push time by
///   `SupabaseSyncBackend.playPayloadFromRow`),
/// - op: `'insert'` (replayed as an idempotent upsert),
/// - payload: `SupabaseSyncBackend.playToPayload` (remote snake_case
///   columns; no user id — attribution is done remotely via RLS).
class PlaysSync {
  /// Creates the queue over the sync outbox.
  PlaysSync({required SyncOutboxDao outboxDao}) : _outboxDao = outboxDao;

  /// Outbox `tableName` for play sessions.
  static const String playsTable = 'plays';

  final SyncOutboxDao _outboxDao;

  /// Enqueues one recorded play row for remote push.
  ///
  /// [track] must be the entity the play belongs to (the fingerprint is
  /// computed from its identity fields, so it matches the remote rows of the
  /// same track on other devices).
  Future<void> enqueuePlay(PlayRow row, Track track) async {
    final fingerprint = playFingerprint(track);
    final payload = SupabaseSyncBackend.playToPayload(
      fingerprint: fingerprint,
      title: track.title,
      artist: track.artist,
      album: track.album,
      source: row.source,
      deviceId: row.deviceId,
      startedAt: row.startedAt,
      listenedMs: row.listenedMs,
      completed: row.completed,
    );
    await _outboxDao.enqueue(
      tableName: playsTable,
      rowKey: '$fingerprint:${row.startedAt.toIso8601String()}',
      op: 'insert',
      payload: jsonEncode(payload),
    );
  }
}

/// Wraps [PlayRecorder] so that every recorded play also lands in the sync
/// outbox ([PlaysSync.enqueuePlay]).
///
/// The just-written `plays` row is fetched back through
/// `playsDao.playsForTrack` (newest first — the row [PlayRecorder] wrote has
/// `startedAt: DateTime.now()`, so it is the newest one for that track).
class PlaysSyncOutboxHook {
  /// Creates the hook; all collaborators come from the provider below.
  PlaysSyncOutboxHook({
    required PlayRecorder recorder,
    required PlaysSync playsSync,
    required PlaysDao playsDao,
  })  : _recorder = recorder,
        _playsSync = playsSync,
        _playsDao = playsDao;

  final PlayRecorder _recorder;
  final PlaysSync _playsSync;
  final PlaysDao _playsDao;

  /// Records the play (via [PlayRecorder]) and enqueues it for sync. Never
  /// throws into the playback engine: an outbox write failure must not break
  /// playback, so it is swallowed after the record succeeded.
  Future<void> record(Track track) async {
    await _recorder.record(track);
    final trackId = track.id;
    if (trackId == null) {
      return;
    }
    try {
      final plays = await _playsDao.playsForTrack(trackId);
      if (plays.isEmpty) {
        return;
      }
      await _playsSync.enqueuePlay(plays.first, track);
    } on Object {
      // Sync is best-effort; local history was already written above.
    }
  }
}

/// Feature-scoped binding over the app database's sync outbox.
final playsSyncProvider = Provider<PlaysSync>((ref) {
  return PlaysSync(outboxDao: ref.watch(databaseProvider).syncOutboxDao);
});

/// Binding for the wrapped play recorder used by the QueueManager
/// `onTrackStarted` hook (see the ORCHESTRATOR WIRING note at the top).
final playsSyncOutboxHookProvider = Provider<PlaysSyncOutboxHook>((ref) {
  return PlaysSyncOutboxHook(
    recorder: ref.watch(playRecorderProvider),
    playsSync: ref.watch(playsSyncProvider),
    playsDao: ref.watch(databaseProvider).playsDao,
  );
});

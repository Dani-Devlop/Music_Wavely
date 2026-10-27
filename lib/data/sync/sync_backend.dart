import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';

/// Transport contract between the local sync engine and the remote backend.
///
/// Implementations:
/// - `SupabaseSyncBackend` (production, built only when
///   `WavelyEnv.hasSupabase` — the provider returns null otherwise, which
///   makes the sync service park in `SyncStatus.disabled`).
/// - fakes in `test/data/sync/sync_service_test.dart`.
///
/// All methods return [Result] instead of throwing: the sync engine must
/// never crash the app over transport problems.
abstract interface class SyncBackend {
  /// Pushes one drained outbox [batch] (oldest first) to the remote tables.
  ///
  /// Rows carry [SyncOutboxRow.tableName] (remote table selector),
  /// [SyncOutboxRow.op] (`insert`/`update`/`delete`) and a JSON
  /// [SyncOutboxRow.payload] in remote column names. Idempotent upserts make
  /// replays after a partial batch safe.
  Future<Result<void>> push(List<SyncOutboxRow> batch);

  /// Fetches remote plays recorded after [since] (exclusive-cutoff semantics
  /// are implemented by the backend; the engine passes the persisted
  /// `wavely.sync.lastPulledAt` stamp, or the epoch on first pull).
  Future<Result<List<RemotePlay>>> pull(DateTime since);
}

/// Optional capability for backends that also mirror `user_settings`.
///
/// Declared separately (instead of a method on [SyncBackend]) so simple
/// backends stay minimal; the engine pulls settings only when the concrete
/// backend implements this interface.
abstract interface class SettingsPullable {
  /// Latest remote settings snapshot, or null when none exists remotely.
  ///
  /// The engine resolves conflicts through `ConflictResolver.resolveSettings`
  /// (last-write-wins on `updatedAt`).
  Future<Result<RemoteSettingsSnapshot?>> pullSettings();
}

/// One remote play record as pulled from the backend.
///
/// Minimal shape on purpose: the remote `plays` table stores the track
/// snapshot (title/artist/album), the [fingerprint] (see
/// `fingerprint.dart` — sha1 over `sourceId:sourceTrackId:title:artist`)
/// and the listening session. Map keys follow the remote snake_case column
/// names; see `SupabaseSyncBackend.playToPayload` for the canonical set.
class RemotePlay {
  /// Creates a remote play record.
  const RemotePlay({
    required this.fingerprint,
    required this.title,
    required this.artist,
    this.album,
    required this.source,
    required this.deviceId,
    required this.startedAt,
    required this.listenedMs,
    required this.completed,
  });

  /// Decodes one remote row (snake_case keys, ISO-8601 `started_at`).
  factory RemotePlay.fromMap(Map<String, dynamic> map) => RemotePlay(
        fingerprint: map['fingerprint'] as String,
        title: map['title'] as String,
        artist: map['artist'] as String,
        album: map['album'] as String?,
        source: map['source'] as String,
        deviceId: map['device_id'] as String,
        startedAt: DateTime.parse(map['started_at'] as String),
        listenedMs: (map['listened_ms'] as num).toInt(),
        completed: map['completed'] as bool,
      );

  /// Identity of the track on the remote side (opaque locally — matching
  /// against local tracks goes through the computed fingerprint).
  final String fingerprint;

  /// Track title snapshot at play time.
  final String title;

  /// Track artist snapshot at play time.
  final String artist;

  /// Track album snapshot, when the remote row carried one.
  final String? album;

  /// Track source id (mirrors the local `sourceId`, e.g. `local`).
  final String source;

  /// Device the session happened on.
  final String deviceId;

  /// Session start (ISO-8601 on the wire). Compared at second precision on
  /// dedupe because the local drift schema stores datetimes as unix seconds.
  final DateTime startedAt;

  /// Listened milliseconds of the session.
  final int listenedMs;

  /// Whether the session ran to completion.
  final bool completed;

  /// Encodes back to the remote snake_case row shape.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'fingerprint': fingerprint,
        'title': title,
        'artist': artist,
        'album': album,
        'source': source,
        'device_id': deviceId,
        'started_at': startedAt.toIso8601String(),
        'listened_ms': listenedMs,
        'completed': completed,
      };
}

/// Remote `user_settings` row: raw payload plus the LWW stamp.
class RemoteSettingsSnapshot {
  /// Creates a snapshot.
  const RemoteSettingsSnapshot({
    required this.payload,
    required this.updatedAt,
  });

  /// Remote settings payload (remote column names, values opaque here —
  /// `ConflictResolver.resolveSettings` only compares timestamps).
  final Map<String, dynamic> payload;

  /// Remote `updated_at` stamp used for last-write-wins.
  final DateTime updatedAt;
}

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/plays_dao.dart';
import 'package:wavely/data/local/db/daos/sync_outbox_dao.dart';
import 'package:wavely/data/local/db/daos/tracks_dao.dart';
import 'package:wavely/data/sync/conflict_resolver.dart';
import 'package:wavely/data/sync/fingerprint.dart';
import 'package:wavely/data/sync/sync_backend.dart';
import 'package:wavely/data/sync/sync_status.dart';

/// Result summary of one [SyncService.pullChanges] round.
class PullResult {
  const PullResult({
    required this.inserted,
    required this.duplicates,
    required this.skipped,
  });

  /// Remote plays written into the local `plays` table.
  final int inserted;

  /// Remote plays dropped because the same (track, started_at second) already
  /// exists locally — the local dedupe rule (see class docs below).
  final int duplicates;

  /// Remote plays whose fingerprint matched NO local track. They are NOT
  /// fabricated into the library; they stay remote-only.
  final int skipped;
}

/// Stage 1.2 sync engine (B4): drains the sync outbox to the remote backend
/// and pulls remote plays back into the local history.
///
/// Push contract
/// -------------
/// `pushChanges` drains [SyncOutboxDao.pending] oldest-first in batches of
/// [batchSize]; a successful backend round deletes the pushed rows, a failed
/// round bumps every row's attempt counter, and rows reaching
/// [SyncOutboxDao.maxAttempts] are "parked" (surfaced by
/// [SyncOutboxDao.failed], skipped by every later drain). The method never
/// throws — transport problems become [SyncStatus.error] on
/// [statusStream].
///
/// Pull contract
/// -------------
/// `pullChanges` fetches remote plays newer than the persisted
/// [lastPulledAtKey] stamp and inserts the ones that can be anchored to the
/// local library:
/// - a remote play matches a local track when its fingerprint (sha1 over
///   `sourceId:sourceTrackId:title:artist`, see `fingerprint.dart`) equals
///   the computed fingerprint of a local track — i.e. identity is matched on
///   the full (source, sourceTrackId, title, artist) tuple, NOT on
///   `sourceTrackId` alone (not unique across sources);
/// - unmatched remote plays are counted as [PullResult.skipped] and never
///   fabricated into the library;
/// - dedupe key locally is (trackId, started-at-second) — the local schema
///   has no user_id/fingerprint columns, and drift stores datetimes as unix
///   seconds, so equality is compared at second precision. This mirrors the
///   spec rule "dedupe by (user_id, fingerprint, started_at)": user_id is
///   implied per device (one local database per user) and the fingerprint is
///   the track identity.
///
/// When the backend also implements [SettingsPullable], each pull round
/// additionally runs the `user_settings` LWW merge through
/// [ConflictResolver.resolveSettings]; the winning snapshot is persisted in
/// the settings store under [localSettingsKey] (the app-side notifier hook
/// that publishes/consumes that snapshot is wired by the orchestrator).
class SyncService {
  /// Builds the engine over the local database and an optional [backend]
  /// (null -> the service emits [SyncStatus.disabled] and idles).
  ///
  /// [settingsStore] persists the pull watermark and the resolved settings
  /// snapshot; the production provider wires the SharedPreferences-backed
  /// store, tests use an in-memory one.
  SyncService({
    required AppDatabase db,
    required SyncOutboxDao outboxDao,
    required PlaysDao playsDao,
    required TracksDao tracksDao,
    required SettingsStore settingsStore,
    SyncBackend? backend,
    this.pushInterval = const Duration(minutes: 5),
  })  : _db = db,
        _outboxDao = outboxDao,
        _playsDao = playsDao,
        _tracksDao = tracksDao,
        _settingsStore = settingsStore,
        _backend = backend {
    _status = SyncStatusView(
      status: backend == null ? SyncStatus.disabled : SyncStatus.idle,
    );
  }

  /// Settings-store key of the last successful pull watermark (ISO-8601).
  static const String lastPulledAtKey = 'wavely.sync.lastPulledAt';

  /// Settings-store key of the resolved `user_settings` snapshot
  /// (`{'payload': {...}, 'updatedAt': iso}`).
  static const String localSettingsKey = 'wavely.sync.userSettings';

  /// Outbox rows per push round.
  static const int batchSize = 50;

  /// How often [start] re-runs push+pull.
  final Duration pushInterval;

  final AppDatabase _db;
  final SyncOutboxDao _outboxDao;
  final PlaysDao _playsDao;
  final TracksDao _tracksDao;
  final SettingsStore _settingsStore;
  final SyncBackend? _backend;

  final StreamController<SyncStatusView> _statusController =
      StreamController<SyncStatusView>.broadcast();

  late SyncStatusView _status;
  String? _lastError;
  Timer? _timer;
  StreamSubscription<bool>? _connectivitySubscription;
  bool _started = false;
  bool _disposed = false;
  bool _pushing = false;
  bool _pulling = false;

  /// Broadcast stream of status snapshots (one per lifecycle change).
  Stream<SyncStatusView> get statusStream => _statusController.stream;

  /// Latest status snapshot (synchronous accessor for first-frame UIs).
  SyncStatusView get status => _status;

  /// Starts the engine: an initial push+pull round, a periodic timer every
  /// [pushInterval], and (when [connectivityChanges] is given) one extra
  /// round on every connectivity regain (`true` event).
  Future<void> start({Stream<bool>? connectivityChanges}) async {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    unawaited(runOnce());
    _timer = Timer.periodic(pushInterval, (_) {
      unawaited(runOnce());
    });
    _connectivitySubscription = connectivityChanges?.listen((online) {
      if (online && !_disposed) {
        unawaited(runOnce());
      }
    });
  }

  /// One full sync round: push the outbox, then pull remote changes.
  Future<void> runOnce() async {
    await pushChanges();
    await pullChanges();
  }

  /// Drives [SyncStatus.syncing] -> idle/error for one push round.
  Future<void> pushChanges() async {
    final backend = _backend;
    if (backend == null || _disposed || _pushing) {
      if (backend == null) {
        await _emit(SyncStatus.disabled);
      }
      return;
    }
    _pushing = true;
    try {
      await _emit(SyncStatus.syncing);
      while (true) {
        final batch = await _outboxDao.pending(limit: batchSize);
        if (batch.isEmpty) {
          break;
        }
        // Parked rows (attempts >= maxAttempts) are skipped forever.
        final pushable = batch
            .where((row) => row.attempts < SyncOutboxDao.maxAttempts)
            .toList(growable: false);
        if (pushable.isEmpty) {
          break;
        }
        final result = await backend.push(pushable);
        if (result.isSuccess) {
          for (final row in pushable) {
            await _outboxDao.remove(row.id);
          }
          continue;
        }
        final failure = switch (result) {
          Err(:final f) => f,
          Success() => null,
        };
        _lastError = _describe(failure);
        for (final row in pushable) {
          await _outboxDao.bumpAttempts(row.id, attempts: row.attempts + 1);
        }
        await _emit(SyncStatus.error);
        return;
      }
      _lastError = null;
      await _emit(SyncStatus.idle);
    } on Object catch (e) {
      // Never let a sync round crash the caller (queue hooks, timers...).
      _lastError = e.toString();
      await _emit(SyncStatus.error);
    } finally {
      _pushing = false;
    }
  }

  /// Drives [SyncStatus.syncing] -> idle/error for one pull round and
  /// returns what the pull did (zeros when disabled or failed).
  Future<PullResult> pullChanges() async {
    final backend = _backend;
    if (backend == null || _disposed || _pulling) {
      if (backend == null) {
        await _emit(SyncStatus.disabled);
      }
      return const PullResult(inserted: 0, duplicates: 0, skipped: 0);
    }
    _pulling = true;
    try {
      await _emit(SyncStatus.syncing);
      final since = await _readLastPulledAt();
      final result = await backend.pull(since);
      if (result.isErr) {
        final failure = switch (result) {
          Err(:final f) => f,
          Success() => null,
        };
        _lastError = _describe(failure);
        await _emit(SyncStatus.error);
        return const PullResult(inserted: 0, duplicates: 0, skipped: 0);
      }
      final plays = result.getOrElse((failure) => const <RemotePlay>[]);
      final outcome = await _applyRemotePlays(plays);
      await _settingsStore.write(
        lastPulledAtKey,
        DateTime.now().toIso8601String(),
      );
      await _pullSettingsIfAvailable(backend);
      _lastError = null;
      await _emit(SyncStatus.idle);
      return outcome;
    } on Object catch (e) {
      _lastError = e.toString();
      await _emit(SyncStatus.error);
      return const PullResult(inserted: 0, duplicates: 0, skipped: 0);
    } finally {
      _pulling = false;
    }
  }

  /// Cancels the timer + connectivity listener and closes the status stream.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _timer?.cancel();
    unawaited(_connectivitySubscription?.cancel());
    unawaited(_statusController.close());
  }

  // -- pull internals --------------------------------------------------------

  Future<PullResult> _applyRemotePlays(List<RemotePlay> plays) async {
    if (plays.isEmpty) {
      return const PullResult(inserted: 0, duplicates: 0, skipped: 0);
    }
    // fingerprint -> local track id (identity match, see class docs).
    final fingerprints = <String, int>{};
    var page = 0;
    while (true) {
      final tracks = await _tracksDao.getAll(
        limit: 200,
        offset: page * 200,
      );
      for (final track in tracks) {
        final id = track.id;
        if (id != null) {
          fingerprints[playFingerprint(track)] = id;
        }
      }
      if (tracks.length < 200) {
        break;
      }
      page++;
    }

    // started-at seconds already recorded per matched track (dedupe cache).
    final knownStarts = <int, Set<int>>{};
    Set<int> startsFor(int trackId) => knownStarts.putIfAbsent(trackId, () {
          return <int>{
            for (final play in _playsDao.playsForTrack(trackId))
              _secondOf(play.startedAt),
          };
        });

    var inserted = 0;
    var duplicates = 0;
    var skipped = 0;
    final inserts = <PlaysCompanion>[];
    for (final play in plays) {
      final trackId = fingerprints[play.fingerprint];
      if (trackId == null) {
        skipped++;
        continue;
      }
      final second = _secondOf(play.startedAt);
      if (startsFor(trackId).contains(second)) {
        duplicates++;
        continue;
      }
      startsFor(trackId).add(second);
      inserts.add(
        PlaysCompanion.insert(
          trackId: trackId,
          startedAt: play.startedAt,
          listenedMs: play.listenedMs,
          completed: Value(play.completed),
          source: play.source,
          deviceId: play.deviceId,
        ),
      );
    }
    if (inserts.isNotEmpty) {
      await _db.transaction(() async {
        for (final insert in inserts) {
          await _playsDao.insertPlay(insert);
        }
      });
      inserted = inserts.length;
    }
    return PullResult(
      inserted: inserted,
      duplicates: duplicates,
      skipped: skipped,
    );
  }

  Future<void> _pullSettingsIfAvailable(SyncBackend backend) async {
    if (backend is! SettingsPullable) {
      return;
    }
    try {
      final result = await backend.pullSettings();
      final snapshot = switch (result) {
        Success<RemoteSettingsSnapshot?>(:final value) => value,
        Err<RemoteSettingsSnapshot?>() => null,
      };
      if (snapshot == null) {
        return;
      }
      final localRaw = await _settingsStore.read<String>(localSettingsKey);
      Map<String, dynamic> localPayload = <String, dynamic>{};
      DateTime? localUpdated;
      if (localRaw != null) {
        final decoded = jsonDecode(localRaw) as Map<String, dynamic>;
        localPayload =
            (decoded['payload'] as Map<String, dynamic>?) ??
                <String, dynamic>{};
        final stamp = decoded['updatedAt'] as String?;
        if (stamp != null) {
          localUpdated = DateTime.tryParse(stamp);
        }
      }
      final resolution = ConflictResolver.resolveSettings(
        local: localPayload,
        remote: snapshot.payload,
        localUpdated: localUpdated,
        remoteUpdated: snapshot.updatedAt,
      );
      if (resolution.winner == SettingsWinner.remote) {
        await _settingsStore.write(
          localSettingsKey,
          jsonEncode(<String, dynamic>{
            'payload': snapshot.payload,
            'updatedAt': snapshot.updatedAt.toIso8601String(),
          }),
        );
      }
    } on Object {
      // Settings LWW is best-effort; a failure must not fail the pull round.
    }
  }

  Future<DateTime> _readLastPulledAt() async {
    final raw = await _settingsStore.read<String>(lastPulledAtKey);
    return DateTime.tryParse(raw ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  // -- status plumbing -------------------------------------------------------

  Future<void> _emit(SyncStatus status) async {
    if (_disposed) {
      return;
    }
    final pending = await _outboxDao.count();
    _status = SyncStatusView(
      status: status,
      pending: pending,
      lastError: _lastError,
    );
    if (!_statusController.isClosed) {
      _statusController.add(_status);
    }
  }

  static int _secondOf(DateTime value) =>
      value.millisecondsSinceEpoch ~/ 1000;

  static String? _describe(Failure? failure) {
    if (failure == null) {
      return null;
    }
    return switch (failure) {
      NetworkFailure(:final message) => message,
      StorageFailure(:final message) => message,
      PermissionFailure(:final message) => message,
      ParsingFailure(:final message) => message,
      UnknownFailure(:final message) => message,
    };
  }
}

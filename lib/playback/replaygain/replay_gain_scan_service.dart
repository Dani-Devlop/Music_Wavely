/// Batch ReplayGain scan service (Phase 8.2).
///
/// Walks the local library (or an explicit track list), measures each file
/// with FFmpeg `ebur128`, stores per-track gain + peak, and backfills
/// album gain per album group. Progress is a broadcast stream; a scan is
/// cancelable between files.
///
/// Foreground-service note: with no Android target in this repository the
/// scan runs as an in-app service (progress UI + cancel). On an Android
/// build the same service class is what a foreground service wrapper would
/// drive — documented in the parity report.
library;

import 'dart:async';

import 'package:wavely/core/audio/ffmpeg_executor.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/audio_cutter/data/cutter_commands.dart'
    show buildEbur128Args;
import 'package:wavely/playback/replaygain/replay_gain_math.dart';

/// Snapshot of a running scan.
class ReplayGainScanState {
  const ReplayGainScanState({
    this.running = false,
    this.total = 0,
    this.completed = 0,
    this.failed = 0,
    this.currentTrack,
  });

  final bool running;

  /// Files still to measure at scan start.
  final int total;

  final int completed;
  final int failed;

  /// Title of the file being measured.
  final String? currentTrack;

  double get progress => total == 0 ? 0 : (completed + failed) / total;

  bool get isDone => !running && total > 0;

  ReplayGainScanState copyWith({
    bool? running,
    int? total,
    int? completed,
    int? failed,
    String? currentTrack,
    bool clearCurrent = false,
  }) =>
      ReplayGainScanState(
        running: running ?? this.running,
        total: total ?? this.total,
        completed: completed ?? this.completed,
        failed: failed ?? this.failed,
        currentTrack: clearCurrent ? null : (currentTrack ?? this.currentTrack),
      );
}

/// Track lookup abstraction (tests inject in-memory fakes).
abstract interface class ReplayGainTrackSource {
  /// Every local track eligible for scanning.
  Future<List<Track>> localTracks();
}

/// Drift-backed source over the local library.
class DriftReplayGainTrackSource implements ReplayGainTrackSource {
  DriftReplayGainTrackSource(this._db);

  final AppDatabase _db;

  @override
  Future<List<Track>> localTracks() =>
      _db.tracksDao.bySource(Track.localSourceId, limit: 100000);
}

/// Album grouping key for the album-gain pass.
String albumKeyOf(Track track) =>
    '${track.artistOrUnknown}||${track.album ?? ''}';

/// The scan service (one instance per app run).
class ReplayGainScanService {
  ReplayGainScanService({
    required FFmpegExecutor executor,
    required AppDatabase db,
    ReplayGainTrackSource? trackSource,
  })  : _executor = executor,
        _db = db,
        _trackSource = trackSource ?? DriftReplayGainTrackSource(db);

  final FFmpegExecutor _executor;
  final AppDatabase _db;
  final ReplayGainTrackSource _trackSource;

  final StreamController<ReplayGainScanState> _stateController =
      StreamController<ReplayGainScanState>.broadcast();
  ReplayGainScanState _state = const ReplayGainScanState();
  bool _cancelRequested = false;
  Completer<void>? _scanDone;

  /// Progress updates (broadcast; late subscribers get the latest via
  /// [currentState] plus subsequent events).
  Stream<ReplayGainScanState> get stateStream => _stateController.stream;

  ReplayGainScanState get currentState => _state;

  bool get isRunning => _state.running;

  void _emit(ReplayGainScanState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  /// Scans the whole local library, skipping tracks whose [Track.id] is
  /// already measured (unless [rescan] is true). Returns when done.
  Future<ReplayGainScanState> scanLibrary({bool rescan = false}) async {
    final List<Track> all = await _trackSource.localTracks();
    List<Track> targets = <Track>[
      for (final Track track in all)
        if (track.id != null && track.filePath != null) track,
    ];
    if (!rescan) {
      final List<int> alreadyScanned =
          await _db.replayGainDao.scannedTrackIds();
      targets = <Track>[
        for (final Track track in targets)
          if (!alreadyScanned.contains(track.id)) track,
      ];
    }
    return _runScan(targets);
  }

  /// Scans an explicit [tracks] list (also the album-gain backfill path).
  Future<ReplayGainScanState> scanTracks(List<Track> tracks) =>
      _runScan(<Track>[
        for (final Track track in tracks)
          if (track.id != null && track.filePath != null) track,
      ]);

  Future<ReplayGainScanState> _runScan(List<Track> targets) async {
    if (_state.running) {
      return _state;
    }
    _cancelRequested = false;
    _scanDone = Completer<void>();
    _emit(
      ReplayGainScanState(
        running: true,
        total: targets.length,
        completed: 0,
        failed: 0,
      ),
    );

    try {
      await _scanLoop(targets);
    } finally {
      _emit(_state.copyWith(running: false, clearCurrent: true));
      _scanDone?.complete();
      _scanDone = null;
    }
    return _state;
  }

  Future<void> _scanLoop(List<Track> targets) async {
    // Track measurements for the album pass.
    final Map<String, List<Track>> albumGroups =
        <String, List<Track>>{};
    final Map<String, List<double>> albumLoudness =
        <String, List<double>>{};
    final Map<String, List<int>> albumTrackIds =
        <String, List<int>>{};

    for (final Track track in targets) {
      if (_cancelRequested) {
        break;
      }
      final String? path = track.filePath;
      final int? id = track.id;
      if (path == null || id == null) {
        continue;
      }
      _emit(_state.copyWith(currentTrack: track.title));
      final LoudnessMeasurement? measurement =
          await _measure(path);
      if (measurement == null) {
        _emit(_state.copyWith(failed: _state.failed + 1));
        continue;
      }
      final double gain =
          replayGainDbFromLoudness(measurement.integratedLufs);
      await _db.replayGainDao.upsertTrack(
        trackId: id,
        trackGainDb: gain,
        peak: measurement.peakLinear,
      );
      final String key = albumKeyOf(track);
      albumGroups.putIfAbsent(key, () => <Track>[]).add(track);
      albumLoudness
          .putIfAbsent(key, () => <double>[])
          .add(measurement.integratedLufs);
      albumTrackIds.putIfAbsent(key, () => <int>[]).add(id);
      _emit(_state.copyWith(completed: _state.completed + 1));
    }

    if (!_cancelRequested) {
      await _backfillAlbumGains(albumLoudness, albumTrackIds);
    }
  }

  Future<void> _backfillAlbumGains(
    Map<String, List<double>> albumLoudness,
    Map<String, List<int>> albumTrackIds,
  ) async {
    for (final String key in albumLoudness.keys) {
      final List<int> ids = albumTrackIds[key]!;
      if (ids.length < 2) {
        // Album gain only meaningful across multiple tracks.
        continue;
      }
      final double albumGain =
          albumGainFromLoudnesses(albumLoudness[key]!);
      await _db.replayGainDao.setAlbumGain(ids, albumGain);
    }
  }

  /// One ebur128 measurement; `null` when FFmpeg failed or parsing found
  /// no integrated loudness.
  Future<LoudnessMeasurement?> _measure(String path) async {
    final FFmpegRunResult result = await _executor.execute(
      buildEbur128Args(path),
    );
    if (!result.success) {
      return null;
    }
    return parseEbur128Log(result.logs ?? '');
  }

  /// Requests cancellation (takes effect between files).
  void cancel() => _cancelRequested = true;

  /// Waits for the current scan to finish (no-op when idle).
  Future<void> awaitCompletion() => _scanDone?.future ?? Future<void>.value();

  Future<void> dispose() async {
    cancel();
    await _stateController.close();
  }
}

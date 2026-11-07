import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/tables/replay_gain.dart';

part 'replay_gain_dao.g.dart';

/// Persistence for per-track ReplayGain measurements (Phase 8.2).
@DriftAccessor(tables: [ReplayGainData])
class ReplayGainDao extends DatabaseAccessor<AppDatabase>
    with _$ReplayGainDaoMixin {
  ReplayGainDao(super.attachedDatabase);

  /// The stored measurement for [trackId], or `null` when unscanned.
  Future<ReplayGainRow?> forTrack(int trackId) {
    return (select(replayGainData)
          ..where((ReplayGainData row) => row.trackId.equals(trackId))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Measurements for many tracks at once (playback pre-fetch).
  Future<List<ReplayGainRow>> forTracks(List<int> trackIds) {
    if (trackIds.isEmpty) {
      return Future<List<ReplayGainRow>>.value(const <ReplayGainRow>[]);
    }
    return (select(replayGainData)
          ..where((ReplayGainData row) => row.trackId.isIn(trackIds)))
        .get();
  }

  /// Upserts a track measurement.
  Future<void> upsertTrack({
    required int trackId,
    required double trackGainDb,
    double? peak,
  }) async {
    final ReplayGainCompanion entry = ReplayGainCompanion.insert(
      trackId: trackId,
      trackGainDb: trackGainDb,
      peak: Value(peak),
      scannedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await into(replayGainData).insert(
      entry,
      onConflict: DoUpdate(
        (_) => ReplayGainCompanion(
          trackGainDb: entry.trackGainDb,
          peak: entry.peak,
          scannedAt: entry.scannedAt,
        ),
        target: <Column<Object>>[replayGainData.trackId],
      ),
    );
  }

  /// Backfills album gain onto a set of track rows (album scan pass).
  Future<void> setAlbumGain(List<int> trackIds, double albumGainDb) async {
    if (trackIds.isEmpty) {
      return;
    }
    await (update(replayGainData)
          ..where((ReplayGainData row) => row.trackId.isIn(trackIds)))
        .write(ReplayGainCompanion(albumGainDb: Value(albumGainDb)));
  }

  /// Removes the measurement of [trackId] (library rescan cleanup hook).
  Future<int> deleteForTrack(int trackId) {
    return (delete(replayGainData)
          ..where((ReplayGainData row) => row.trackId.equals(trackId)))
        .go();
  }

  /// All scanned track ids (scan UI: "already analyzed" filtering).
  Future<List<int>> scannedTrackIds() async {
    final List<ReplayGainRow> rows = await select(replayGainData).get();
    return <int>[for (final ReplayGainRow row in rows) row.trackId];
  }
}

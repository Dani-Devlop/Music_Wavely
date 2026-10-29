import 'package:wavely/data/local/db/tables/plays.dart';
import 'package:wavely/data/local/db/tables/tracks.dart';
import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/mappers/track_mapper.dart';
import 'package:wavely/domain/entities/entities.dart';

part 'plays_dao.g.dart';

/// Data access for [Plays] (listening history) and the track-level playback
/// statistics derived from it.
@DriftAccessor(tables: [Plays, Tracks])
class PlaysDao extends DatabaseAccessor<AppDatabase> with _$PlaysDaoMixin {
  PlaysDao(super.attachedDatabase);

  /// Default page size for [topTracks].
  static const int defaultTopLimit = 10;

  /// Records one listening session.
  Future<int> insertPlay(PlaysCompanion entry) => into(plays).insert(entry);

  /// All recorded sessions of a track, newest first.
  Future<List<PlayRow>> playsForTrack(int trackId) =>
      (select(plays)
            ..where((p) => p.trackId.equals(trackId))
            ..orderBy([(p) => OrderingTerm.desc(p.startedAt)]))
          .get();

  /// Sum of all listened milliseconds across the whole history.
  Future<int> totalListenedMs() async {
    final sum = plays.listenedMs.sum();
    final query = selectOnly(plays)..addColumns([sum]);
    final row = await query.getSingle();
    return row.read(sum) ?? 0;
  }

  /// The most-played tracks, ordered by play count descending (ties broken
  /// by track id for stable pagination).
  Future<List<Track>> topTracks({int limit = defaultTopLimit}) async {
    final rows = await customSelect(
      'SELECT track_id, COUNT(*) AS play_total '
      'FROM plays '
      'GROUP BY track_id '
      'ORDER BY play_total DESC, track_id ASC '
      'LIMIT ?',
      variables: [Variable.withInt(limit)],
    ).get();
    final ids = <int>[for (final row in rows) row.read<int>('track_id')];
    if (ids.isEmpty) {
      return const <Track>[];
    }
    final trackRows =
        await (select(tracks)..where((t) => t.id.isIn(ids))).get();
    final byId = <int, TracksRow>{
      for (final row in trackRows) row.id: row,
    };
    return <Track>[
      for (final id in ids)
        if (byId[id] case final row?) TrackMapper.toDomain(row),
    ];
  }

  /// [topTracks] with each track's exact play total attached, so callers
  /// (discovery seeding) can weight artists by real play intensity instead
  /// of counting rows once per track.
  Future<List<(Track, int)>> topTracksWithCounts({
    int limit = defaultTopLimit,
  }) async {
    final rows = await customSelect(
      'SELECT track_id, COUNT(*) AS play_total '
      'FROM plays '
      'GROUP BY track_id '
      'ORDER BY play_total DESC, track_id ASC '
      'LIMIT ?',
      variables: [Variable.withInt(limit)],
    ).get();
    final ids = <int>[for (final row in rows) row.read<int>('track_id')];
    if (ids.isEmpty) {
      return const <(Track, int)>[];
    }
    final totals = <int, int>{
      for (final row in rows) row.read<int>('track_id'): row.read<int>(
        'play_total',
      ),
    };
    final trackRows =
        await (select(tracks)..where((t) => t.id.isIn(ids))).get();
    final byId = <int, TracksRow>{
      for (final row in trackRows) row.id: row,
    };
    return <(Track, int)>[
      for (final id in ids)
        if (byId[id] case final row?) (TrackMapper.toDomain(row), totals[id] ?? 0),
    ];
  }

  /// Bumps the play statistics of [trackId]: `playCount + 1` and
  /// `lastPlayedAt = now` in a single SQL statement.
  Future<void> incrementTrackPlayStats(int trackId) {
    return (update(attachedDatabase.tracks)..where((t) => t.id.equals(trackId))).write(
      TracksCompanion.custom(
        playCount: const CustomExpression<int>('play_count + 1'),
        lastPlayedAt: Variable.withDateTime(DateTime.now()),
      ),
    );
  }
}

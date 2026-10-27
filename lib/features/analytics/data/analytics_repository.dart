import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/plays_dao.dart';
import 'package:wavely/data/local/db/daos/sync_outbox_dao.dart';
import 'package:wavely/data/local/db/daos/tracks_dao.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/data/sync/fingerprint.dart';
import 'package:wavely/domain/entities/entities.dart';

/// Time window of an analytics query.
enum AnalyticsPeriod {
  /// Start of the current day.
  today,

  /// Rolling last 7 days (today inclusive).
  week,

  /// Rolling last 30 days (today inclusive).
  month,

  /// Current calendar year.
  year,

  /// Everything ever recorded.
  lifetime,
}

/// Window helpers for [AnalyticsPeriod].
///
/// `end` is always the last millisecond of the included day so that
/// `started_at >= start AND started_at <= end` covers full days.
extension AnalyticsPeriodX on AnalyticsPeriod {
  /// Resolves the window against [now] (injectable for tests).
  DateTimeRange window(DateTime now) {
    final dayStart = DateTime(now.year, now.month, now.day);
    return switch (this) {
      AnalyticsPeriod.today => DateTimeRange(
          start: dayStart,
          end: _endOfDay(dayStart),
        ),
      AnalyticsPeriod.week => DateTimeRange(
          start: dayStart.subtract(const Duration(days: 6)),
          end: _endOfDay(dayStart),
        ),
      AnalyticsPeriod.month => DateTimeRange(
          start: dayStart.subtract(const Duration(days: 29)),
          end: _endOfDay(dayStart),
        ),
      AnalyticsPeriod.year => DateTimeRange(
          start: DateTime(now.year, DateTime.january, 1),
          end: _endOfDay(DateTime(now.year, DateTime.december, 31)),
        ),
      AnalyticsPeriod.lifetime => DateTimeRange(
          start: DateTime.fromMillisecondsSinceEpoch(0),
          end: _endOfDay(dayStart),
        ),
    };
  }

  /// Chip / section label.
  String get label => switch (this) {
        AnalyticsPeriod.today => 'Today',
        AnalyticsPeriod.week => 'Week',
        AnalyticsPeriod.month => 'Month',
        AnalyticsPeriod.year => 'Year',
        AnalyticsPeriod.lifetime => 'Lifetime',
      };
}

DateTime _endOfDay(DateTime dayStart) => DateTime(
      dayStart.year,
      dayStart.month,
      dayStart.day + 1,
    ).subtract(const Duration(milliseconds: 1));

/// One aggregated row of the top-tracks / top-of-year lists.
class TopEntry {
  const TopEntry({
    required this.track,
    required this.plays,
    required this.listenedMs,
  });

  /// The track (library entity, so tiles can render it directly).
  final Track track;

  /// Number of play sessions in the window.
  final int plays;

  /// Sum of listened milliseconds in the window.
  final int listenedMs;
}

/// One row of the top-artists list.
///
/// (Not [TopEntry]: artist rows have no single track entity.)
class ArtistEntry {
  const ArtistEntry({
    required this.artist,
    required this.plays,
    required this.listenedMs,
  });

  /// Artist name as stored on the tracks.
  final String artist;

  /// Number of play sessions across all of the artist's tracks.
  final int plays;

  /// Sum of listened milliseconds across the artist's tracks.
  final int listenedMs;
}

/// One row of the top-genres list.
class GenreCount {
  const GenreCount({required this.genre, required this.plays});

  /// Genre tag as stored on the tracks.
  final String genre;

  /// Number of play sessions of the genre's tracks.
  final int plays;
}

/// Read-side analytics over the local listening history plus the outgoing
/// daily-aggregate batch for the sync engine.
///
/// SQL runs through `db.customSelect` (the period windows are not worth
/// DAO methods); row->entity mapping reuses [TracksDao.byIds] so generated
/// bool/DateTime decoding applies. All aggregate queries share the same
/// window predicate: `started_at >= start AND started_at <= end`.
class AnalyticsRepository {
  /// Builds the repository over the app database.
  AnalyticsRepository({
    required AppDatabase db,
    required TracksDao tracksDao,
    required PlaysDao playsDao,
    required SyncOutboxDao outboxDao,
  })  : _db = db,
        _tracksDao = tracksDao,
        _playsDao = playsDao,
        _outboxDao = outboxDao;

  /// A play counts as skipped when it did not run to completion OR it was
  /// abandoned below this threshold (completed-but-nearly-unlistened
  /// sessions would otherwise hide behind a flaky `completed` flag).
  static const int skipThresholdMs = 30000;

  final AppDatabase _db;
  final TracksDao _tracksDao;
  final PlaysDao _playsDao;
  final SyncOutboxDao _outboxDao;

  /// Total listened milliseconds within [period]'s window.
  Future<int> getTotalListeningTime(
    AnalyticsPeriod period, {
    DateTime? now,
  }) async {
    final window = period.window(now ?? DateTime.now());
    final row = await _db.customSelect(
      'SELECT COALESCE(SUM(listened_ms), 0) AS total '
      'FROM plays WHERE started_at >= ? AND started_at <= ?',
      variables: [
        Variable.withDateTime(window.start),
        Variable.withDateTime(window.end),
      ],
    ).getSingle();
    return row.read<int>('total');
  }

  /// Most-played tracks within [period], ordered by play count (ties by
  /// listened time, then track id for stable pagination).
  Future<List<TopEntry>> getTopTracks(
    AnalyticsPeriod period, {
    int limit = 10,
    DateTime? now,
  }) {
    final window = period.window(now ?? DateTime.now());
    return _topTracksBetween(
      start: window.start,
      end: window.end,
      limit: limit,
    );
  }

  /// Most-played artists (grouped over `tracks.artist`, case-insensitive).
  Future<List<ArtistEntry>> getTopArtists(
    AnalyticsPeriod period, {
    int limit = 8,
    DateTime? now,
  }) async {
    final window = period.window(now ?? DateTime.now());
    final rows = await _db.customSelect(
      'SELECT t.artist AS artist_name, COUNT(*) AS play_count, '
      'SUM(p.listened_ms) AS listened_ms '
      'FROM plays p JOIN tracks t ON t.id = p.track_id '
      'WHERE p.started_at >= ? AND p.started_at <= ? '
      'GROUP BY t.artist COLLATE NOCASE '
      'ORDER BY play_count DESC, listened_ms DESC, artist_name ASC '
      'LIMIT ?',
      variables: [
        Variable.withDateTime(window.start),
        Variable.withDateTime(window.end),
        Variable.withInt(limit),
      ],
    ).get();
    return <ArtistEntry>[
      for (final row in rows)
        ArtistEntry(
          artist: row.read<String>('artist_name'),
          plays: row.read<int>('play_count'),
          listenedMs: row.read<int>('listened_ms'),
        ),
    ];
  }

  /// Most-played genre tags (tracks without a genre are ignored).
  Future<List<GenreCount>> getTopGenres(
    AnalyticsPeriod period, {
    int limit = 5,
    DateTime? now,
  }) async {
    final window = period.window(now ?? DateTime.now());
    final rows = await _db.customSelect(
      'SELECT t.genre AS genre, COUNT(*) AS play_count '
      'FROM plays p JOIN tracks t ON t.id = p.track_id '
      'WHERE p.started_at >= ? AND p.started_at <= ? '
      "AND t.genre IS NOT NULL AND t.genre != '' "
      'GROUP BY t.genre COLLATE NOCASE '
      'ORDER BY play_count DESC, genre ASC '
      'LIMIT ?',
      variables: [
        Variable.withDateTime(window.start),
        Variable.withDateTime(window.end),
        Variable.withInt(limit),
      ],
    ).get();
    return <GenreCount>[
      for (final row in rows)
        GenreCount(
          genre: row.read<String>('genre'),
          plays: row.read<int>('play_count'),
        ),
    ];
  }

  /// Fraction of plays in [period] that count as skipped — see
  /// [skipThresholdMs] for the rule. Returns 0 for an empty window.
  Future<double> getSkipRate(AnalyticsPeriod period, {DateTime? now}) async {
    final window = period.window(now ?? DateTime.now());
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS total, '
      'SUM(CASE WHEN completed = 0 OR listened_ms < ? '
      'THEN 1 ELSE 0 END) AS skips '
      'FROM plays WHERE started_at >= ? AND started_at <= ?',
      variables: [
        Variable.withInt(skipThresholdMs),
        Variable.withDateTime(window.start),
        Variable.withDateTime(window.end),
      ],
    ).getSingle();
    final total = row.read<int>('total');
    if (total == 0) {
      return 0;
    }
    return row.read<int>('skips') / total;
  }

  /// All-time most-played tracks (delegates to [PlaysDao.topTracks]).
  Future<List<Track>> getLifetimeFavorites({int limit = 50}) =>
      _playsDao.topTracks(limit: limit);

  /// Tracks played at least [minPlays] times in the last [withinDays] days,
  /// most-played first ("On Repeat").
  Future<List<Track>> getOnRepeat({
    int withinDays = 7,
    int minPlays = 3,
    DateTime? now,
  }) async {
    final reference = now ?? DateTime.now();
    final start = DateTime(reference.year, reference.month, reference.day)
        .subtract(Duration(days: withinDays));
    final rows = await _db.customSelect(
      'SELECT track_id, COUNT(*) AS play_count '
      'FROM plays WHERE started_at >= ? '
      'GROUP BY track_id HAVING COUNT(*) >= ? '
      'ORDER BY play_count DESC, track_id ASC',
      variables: [
        Variable.withDateTime(start),
        Variable.withInt(minPlays),
      ],
    ).get();
    final ids = <int>[for (final row in rows) row.read<int>('track_id')];
    return _tracksInIdOrder(ids);
  }

  /// Most-played tracks of one calendar year ("Your Top {year}").
  Future<List<TopEntry>> getTopOfYear(
    int year, {
    int limit = 10,
  }) {
    return _topTracksBetween(
      start: DateTime(year, DateTime.january, 1),
      end: DateTime(year + 1, DateTime.january, 1)
          .subtract(const Duration(milliseconds: 1)),
      limit: limit,
    );
  }

  /// Rebuilds the per-track daily aggregates for [day] and enqueues ONE
  /// outbox row (`tableName: 'track_stats_daily'`, `op: 'upsert'`,
  /// `rowKey: yyyy-MM-dd`) whose payload is the whole batch:
  /// `{'day': ..., 'entries': [{'fingerprint', 'plays', 'listened_ms'}]}`.
  ///
  /// There is deliberately NO local `track_stats_daily` mirror table — the
  /// aggregates live remotely (Supabase); `SupabaseSyncBackend` expands the
  /// batch into one upsert per entry when it pushes the row. Enqueues even
  /// when the day has no plays: an empty batch keeps the remote day in sync
  /// (zeroes) after local deletions.
  Future<void> syncDailyAggregates(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final rows = await _db.customSelect(
      'SELECT p.source AS source, t.source_track_id AS source_track_id, '
      't.title AS title, t.artist AS artist, '
      'COUNT(*) AS play_count, SUM(p.listened_ms) AS listened_ms '
      'FROM plays p JOIN tracks t ON t.id = p.track_id '
      'WHERE p.started_at >= ? AND p.started_at < ? '
      'GROUP BY p.source, t.source_track_id, t.title, t.artist',
      variables: [
        Variable.withDateTime(start),
        Variable.withDateTime(end),
      ],
    ).get();
    final dayKey =
        '${start.year.toString().padLeft(4, '0')}-'
        '${start.month.toString().padLeft(2, '0')}-'
        '${start.day.toString().padLeft(2, '0')}';
    final payload = jsonEncode(<String, dynamic>{
      'day': dayKey,
      'entries': <Map<String, dynamic>>[
        for (final row in rows)
          <String, dynamic>{
            'fingerprint': playFingerprintOf(
              sourceId: row.read<String>('source'),
              sourceTrackId: row.read<String>('source_track_id'),
              title: row.read<String>('title'),
              artist: row.read<String>('artist'),
            ),
            'plays': row.read<int>('play_count'),
            'listened_ms': row.read<int>('listened_ms'),
          },
      ],
    });
    await _outboxDao.enqueue(
      tableName: 'track_stats_daily',
      rowKey: dayKey,
      op: 'upsert',
      payload: payload,
    );
  }

  Future<List<TopEntry>> _topTracksBetween({
    required DateTime start,
    required DateTime end,
    required int limit,
  }) async {
    final rows = await _db.customSelect(
      'SELECT track_id, COUNT(*) AS play_count, '
      'SUM(listened_ms) AS listened_ms '
      'FROM plays WHERE started_at >= ? AND started_at <= ? '
      'GROUP BY track_id '
      'ORDER BY play_count DESC, listened_ms DESC, track_id ASC '
      'LIMIT ?',
      variables: [
        Variable.withDateTime(start),
        Variable.withDateTime(end),
        Variable.withInt(limit),
      ],
    ).get();
    final ids = <int>[for (final row in rows) row.read<int>('track_id')];
    if (ids.isEmpty) {
      return const <TopEntry>[];
    }
    final counts = <int, (int, int)>{
      for (final row in rows)
        row.read<int>('track_id'): (
          row.read<int>('play_count'),
          row.read<int>('listened_ms'),
        ),
    };
    final tracks = await _tracksDao.byIds(ids);
    final byId = <int, Track>{
      for (final track in tracks)
        if (track.id case final id?) id: track,
    };
    return <TopEntry>[
      for (final id in ids)
        if (byId[id] case final track?)
          TopEntry(
            track: track,
            plays: counts[id]!.$1,
            listenedMs: counts[id]!.$2,
          ),
    ];
  }

  /// Resolves track ids to entities preserving [ids] order (skips ids that
  /// no longer exist, e.g. after a rescan).
  Future<List<Track>> _tracksInIdOrder(List<int> ids) async {
    if (ids.isEmpty) {
      return const <Track>[];
    }
    final tracks = await _tracksDao.byIds(ids);
    final byId = <int, Track>{
      for (final track in tracks)
        if (track.id case final id?) id: track,
    };
    return <Track>[
      for (final id in ids)
        if (byId[id] case final track?) track,
    ];
  }
}

/// Feature-scoped analytics binding over the app database.
final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return AnalyticsRepository(
    db: db,
    tracksDao: db.tracksDao,
    playsDao: db.playsDao,
    outboxDao: db.syncOutboxDao,
  );
});

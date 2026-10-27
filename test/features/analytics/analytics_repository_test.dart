// authored, awaiting local run.
//
// Tests for lib/features/analytics/data/analytics_repository.dart over a
// memory drift database: a deterministic 100-play seed spread across
// today / week / month / year / lifetime buckets (via the real write path —
// TracksDao.upsertBySource + PlaysDao.insertPlay), then per-Period math for
// getTotalListeningTime / getTopTracks / getTopArtists / getTopGenres /
// getSkipRate, the "On Repeat" (≥3 plays last 7 days) and "Top of year"
// helpers, the period-window helpers, and syncDailyAggregates' single
// outbox batch row (incl. the empty-day contract).
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/sync/fingerprint.dart';
import 'package:wavely/features/analytics/data/analytics_repository.dart';

AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

/// The fixed reference instant every window math runs against.
final DateTime _now = DateTime(2026, 6, 15, 12);

// Bucket day keys used by the seed.
final _today = DateTime(2026, 6, 15);
final _yesterday = DateTime(2026, 6, 14);
final _tenDaysAgo = DateTime(2026, 6, 5); // outside the 7-day window
final _inMonth = DateTime(2026, 6, 1);
final _inMonthOlder = DateTime(2026, 5, 20);
final _inYear = DateTime(2026, 2, 10);
final _in2025 = DateTime(2025, 11, 5);
final _in2024 = DateTime(2024, 3, 3);

class _Seed {
  _Seed(this.db);

  final AppDatabase db;
  final Map<String, Track> _tracks = <String, Track>{};

  Future<Track> track(
    String key, {
    required String artist,
    String? genre,
  }) async {
    final existing = _tracks[key];
    if (existing != null) {
      return existing;
    }
    final track = await db.tracksDao.upsertBySource(
      TracksCompanion.insert(
        sourceId: 'local',
        sourceTrackId: 'st-$key',
        title: 'Track $key',
        artist: artist,
        durationMs: 100000,
        format: 'mp3',
        addedAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
        genre: Value(genre),
      ),
    );
    return _tracks[key] = track;
  }

  Future<void> play(
    Track track,
    DateTime day, {
    required int atMinute,
    int listenedMs = 60000,
    bool completed = true,
  }) {
    final startedAt = DateTime(
      day.year,
      day.month,
      day.day,
      8,
      atMinute,
    );
    return db.playsDao.insertPlay(
      PlaysCompanion.insert(
        trackId: track.id!,
        startedAt: startedAt,
        listenedMs: listenedMs,
        completed: Value(completed),
        source: 'local',
        deviceId: 'device-1',
      ),
    );
  }

  /// Plays [count] sessions of [track] on [day] starting at minute
  /// [firstMinute], one minute apart.
  Future<void> plays(
    Track track,
    DateTime day,
    int count, {
    int firstMinute = 0,
    int listenedMs = 60000,
    bool completed = true,
  }) async {
    for (var i = 0; i < count; i++) {
      await play(
        track,
        day,
        atMinute: firstMinute + i,
        listenedMs: listenedMs,
        completed: completed,
      );
    }
  }
}

/// Seeds the full deterministic 100-play history:
///
/// bucket            plays   tracks
/// 2026-06-15 (today)   32    t1×10, t2×5, t3×5, t6×8, t8×4(skip)
/// 2026-06-14           11    t1×10, t10×1(skip-by-threshold)
/// 2026-06-05            7    t2×5, t9×2 (in month/year, outside week)
/// 2026-06-01            5    t1×5
/// 2026-05-20           10    t4×10
/// 2026-02-10           15    t2×10, t7×5
/// 2025-11-05           10    t3×10
/// 2024-03-03           10    t5×10
Future<Map<String, Track>> _seedLibrary(AppDatabase db) async {
  final seed = _Seed(db);
  final t1 = await seed.track('t1', artist: 'Aurora Waves', genre: 'rock');
  final t2 = await seed.track('t2', artist: 'Aurora Waves', genre: 'rock');
  final t3 = await seed.track('t3', artist: 'Basalt Kings', genre: 'jazz');
  final t4 = await seed.track('t4', artist: 'Basalt Kings', genre: 'pop');
  final t5 = await seed.track('t5', artist: 'Cedar Choir'); // no genre
  final t6 = await seed.track('t6', artist: 'Cedar Choir', genre: '');
  final t7 = await seed.track('t7', artist: 'Cedar Choir', genre: 'ambient');
  final t8 = await seed.track('t8', artist: 'Delta Foxes', genre: 'pop');
  final t9 = await seed.track('t9', artist: 'Delta Foxes', genre: 'jazz');
  final t10 = await seed.track('t10', artist: 'Delta Foxes'); // no genre

  // today (32 plays)
  await seed.plays(t1, _today, 10, firstMinute: 0);
  await seed.plays(t2, _today, 5, firstMinute: 60);
  await seed.plays(t3, _today, 5, firstMinute: 120);
  await seed.plays(t6, _today, 8, firstMinute: 180);
  // t8 = abandoned sessions: 5 s each, not completed.
  await seed.plays(t8, _today, 4, firstMinute: 240, listenedMs: 5000,
      completed: false);
  // 06-14 (11)
  await seed.plays(t1, _yesterday, 10, firstMinute: 0);
  await seed.plays(t10, _yesterday, 1, firstMinute: 60, listenedMs: 20000);
  // 06-10 (7)
  await seed.plays(t2, _tenDaysAgo, 5, firstMinute: 0);
  await seed.plays(t9, _tenDaysAgo, 2, firstMinute: 30);
  // 06-01 (5)
  await seed.plays(t1, _inMonth, 5, firstMinute: 0);
  // 05-20 (10)
  await seed.plays(t4, _inMonthOlder, 10, firstMinute: 0);
  // 2026-02-10 (15)
  await seed.plays(t2, _inYear, 10, firstMinute: 0);
  await seed.plays(t7, _inYear, 5, firstMinute: 30);
  // 2025 + 2024 (20)
  await seed.plays(t3, _in2025, 10, firstMinute: 0);
  await seed.plays(t5, _in2024, 10, firstMinute: 0);

  return <String, Track>{
    't1': t1, 't2': t2, 't3': t3, 't4': t4, 't5': t5,
    't6': t6, 't7': t7, 't8': t8, 't9': t9, 't10': t10,
  };
}

void main() {
  late AppDatabase db;
  late AnalyticsRepository repository;
  late Map<String, Track> tracks;

  setUp(() async {
    db = _memoryDb();
    tracks = await _seedLibrary(db);
    repository = AnalyticsRepository(
      db: db,
      tracksDao: db.tracksDao,
      playsDao: db.playsDao,
      outboxDao: db.syncOutboxDao,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('period windows (AnalyticsPeriodX.window)', () {
    test('today / week / month cover rolling day windows ending tonight',
        () {
      final today = AnalyticsPeriod.today.window(_now);
      expect(today.start, DateTime(2026, 6, 15));
      expect(today.end, DateTime(2026, 6, 15, 23, 59, 59, 999));

      final week = AnalyticsPeriod.week.window(_now);
      expect(week.start, DateTime(2026, 6, 9)); // today − 6 days
      expect(week.end, today.end);

      final month = AnalyticsPeriod.month.window(_now);
      expect(month.start, DateTime(2026, 5, 17)); // today − 29 days
      expect(month.end, today.end);
    });

    test('year covers the calendar year; lifetime starts at the epoch',
        () {
      final year = AnalyticsPeriod.year.window(_now);
      expect(year.start, DateTime(2026, 1, 1));
      expect(year.end, DateTime(2026, 12, 31, 23, 59, 59, 999));

      final lifetime = AnalyticsPeriod.lifetime.window(_now);
      expect(lifetime.start, DateTime.fromMillisecondsSinceEpoch(0));
      expect(lifetime.end, DateTime(2026, 6, 15, 23, 59, 59, 999));
    });

    test('labels match the UI chips', () {
      expect(AnalyticsPeriod.today.label, 'Today');
      expect(AnalyticsPeriod.week.label, 'Week');
      expect(AnalyticsPeriod.month.label, 'Month');
      expect(AnalyticsPeriod.year.label, 'Year');
      expect(AnalyticsPeriod.lifetime.label, 'Lifetime');
    });
  });

  group('getTotalListeningTime', () {
    test('sums listened_ms per period (seed: 100 plays, see table)',
        () async {
      // today: 28 × 60 s + 4 × 5 s
      expect(
        await repository.getTotalListeningTime(AnalyticsPeriod.today,
            now: _now),
        1700000,
      );
      // week: 45 × 60 s + 4 × 5 s + 1 × 20 s
      expect(
        await repository.getTotalListeningTime(AnalyticsPeriod.week,
            now: _now),
        2740000,
      );
      // month: week + 2026-06-01 (5) + 2026-05-20 (10)
      expect(
        await repository.getTotalListeningTime(AnalyticsPeriod.month,
            now: _now),
        3040000,
      );
      // year: month + 2026-02-10 (15)
      expect(
        await repository.getTotalListeningTime(AnalyticsPeriod.year,
            now: _now),
        3940000,
      );
      // lifetime: everything
      expect(
        await repository.getTotalListeningTime(AnalyticsPeriod.lifetime,
            now: _now),
        5740000,
      );
    });

    test('an empty window sums to zero', () async {
      final empty = await repository.getTotalListeningTime(
        AnalyticsPeriod.today,
        now: DateTime(2030, 1, 1),
      );
      expect(empty, 0);
    });
  });

  group('getTopTracks', () {
    test('lifetime top 3 are ordered by play count with correct math',
        () async {
      final top = await repository.getTopTracks(
        AnalyticsPeriod.lifetime,
        limit: 3,
        now: _now,
      );

      expect(
        [for (final entry in top) entry.track.id],
        <int?>[tracks['t1']!.id, tracks['t2']!.id, tracks['t3']!.id],
      );
      expect(
        [for (final entry in top) entry.plays],
        <int>[25, 20, 15],
      );
      expect(
        [for (final entry in top) entry.listenedMs],
        <int>[1500000, 1200000, 900000],
      );
    });

    test('ties break by listened time then track id', () async {
      final top = await repository.getTopTracks(
        AnalyticsPeriod.lifetime,
        limit: 6,
        now: _now,
      );

      // t4/t5 both have 10 plays × 60 s → track id ascending.
      expect(
        [for (final entry in top) entry.track.id],
        <int?>[
          tracks['t1']!.id,
          tracks['t2']!.id,
          tracks['t3']!.id,
          tracks['t4']!.id,
          tracks['t5']!.id,
          tracks['t6']!.id, // 8 plays
        ],
      );
    });

    test('today window only counts today\'s plays', () async {
      final top = await repository.getTopTracks(
        AnalyticsPeriod.today,
        limit: 10,
        now: _now,
      );

      expect(
        [for (final entry in top) entry.track.id],
        <int?>[tracks['t1']!.id, tracks['t6']!.id, tracks['t2']!.id,
            tracks['t3']!.id, tracks['t8']!.id],
      );
      expect(
        [for (final entry in top) entry.plays],
        <int>[10, 8, 5, 5, 4],
      );
      // t8 listened only 4 × 5 s.
      expect(top.last.listenedMs, 20000);
    });

    test('an empty window yields no entries', () async {
      final top = await repository.getTopTracks(
        AnalyticsPeriod.today,
        now: DateTime(2030, 1, 1),
      );
      expect(top, isEmpty);
    });
  });

  group('getTopArtists', () {
    test('lifetime aggregation groups case-insensitively with correct '
        'totals', () async {
      final artists = await repository.getTopArtists(
        AnalyticsPeriod.lifetime,
        limit: 8,
        now: _now,
      );

      expect(
        [for (final entry in artists) entry.artist],
        <String>['Aurora Waves', 'Basalt Kings', 'Cedar Choir', 'Delta Foxes'],
      );
      expect(
        [for (final entry in artists) entry.plays],
        <int>[45, 25, 23, 7],
      );
      expect(
        [for (final entry in artists) entry.listenedMs],
        <int>[2700000, 1500000, 1380000, 160000],
      );
    });

    test('today window re-ranks the artists', () async {
      final artists = await repository.getTopArtists(
        AnalyticsPeriod.today,
        limit: 8,
        now: _now,
      );

      expect(
        [for (final entry in artists) entry.artist],
        <String>['Aurora Waves', 'Cedar Choir', 'Basalt Kings', 'Delta Foxes'],
      );
      expect(
        [for (final entry in artists) entry.plays],
        <int>[15, 8, 5, 4],
      );
    });
  });

  group('getTopGenres', () {
    test('lifetime genres are ranked and null/empty genre plays are '
        'ignored', () async {
      final genres = await repository.getTopGenres(
        AnalyticsPeriod.lifetime,
        limit: 5,
        now: _now,
      );

      expect(
        [for (final genre in genres) genre.genre],
        <String>['rock', 'jazz', 'pop', 'ambient'],
      );
      expect(
        [for (final genre in genres) genre.plays],
        <int>[45, 17, 14, 5],
      );
    });

    test('today window ranks genres within the day', () async {
      final genres = await repository.getTopGenres(
        AnalyticsPeriod.today,
        limit: 5,
        now: _now,
      );

      expect(
        [for (final genre in genres) genre.genre],
        <String>['rock', 'jazz', 'pop'],
      );
      expect(
        [for (final genre in genres) genre.plays],
        <int>[15, 5, 4],
      );
    });
  });

  group('getSkipRate', () {
    test('skips = not completed OR below the 30 s threshold', () async {
      // today: t8's 4 abandoned sessions → 4 / 32.
      expect(
        await repository.getSkipRate(AnalyticsPeriod.today, now: _now),
        4 / 32,
      );
      // week: + t10's completed-but-20 s play → 5 / 50.
      expect(
        await repository.getSkipRate(AnalyticsPeriod.week, now: _now),
        0.1,
      );
      // lifetime: 5 / 100.
      expect(
        await repository.getSkipRate(AnalyticsPeriod.lifetime, now: _now),
        0.05,
      );
    });

    test('an empty window returns 0 (not NaN)', () async {
      expect(
        await repository.getSkipRate(
          AnalyticsPeriod.today,
          now: DateTime(2030, 1, 1),
        ),
        0,
      );
    });
  });

  group('"On Repeat" (getOnRepeat)', () {
    test('only tracks with ≥ minPlays inside the last 7 days, most-played '
        'first', () async {
      final onRepeat = await repository.getOnRepeat(now: _now);

      // Window: 2026-06-08 00:00 → now. In-window counts:
      // t1 20, t2 10, t6 8, t3 5, t8 4 (t9 2 and t10 1 miss the floor,
      // 2026-06-01 and older are outside the window entirely).
      expect(
        [for (final track in onRepeat) track.id],
        <int?>[
          tracks['t1']!.id,
          tracks['t2']!.id,
          tracks['t6']!.id,
          tracks['t3']!.id,
          tracks['t8']!.id,
        ],
      );
    });

    test('a stricter floor filters the list', () async {
      final onRepeat = await repository.getOnRepeat(
        now: _now,
        minPlays: 10,
      );

      expect(
        [for (final track in onRepeat) track.id],
        <int?>[tracks['t1']!.id, tracks['t2']!.id],
      );
    });
  });

  group('"Top of year" (getTopOfYear)', () {
    test('counts plays of the requested calendar year only', () async {
      final top2026 = await repository.getTopOfYear(2026, limit: 3);

      expect(
        [for (final entry in top2026) entry.track.id],
        <int?>[tracks['t1']!.id, tracks['t2']!.id, tracks['t4']!.id],
      );
      expect(
        [for (final entry in top2026) entry.plays],
        <int>[25, 20, 10],
      );

      final top2025 = await repository.getTopOfYear(2025);
      expect(
        [for (final entry in top2025) entry.track.id],
        <int?>[tracks['t3']!.id],
      );

      final top2024 = await repository.getTopOfYear(2024);
      expect(
        [for (final entry in top2024) entry.track.id],
        <int?>[tracks['t5']!.id],
      );

      final top2019 = await repository.getTopOfYear(2019);
      expect(top2019, isEmpty);
    });
  });

  group('getLifetimeFavorites', () {
    test('delegates to the all-time most-played tracks', () async {
      final favorites = await repository.getLifetimeFavorites(limit: 3);

      expect(
        [for (final track in favorites) track.id],
        <int?>[tracks['t1']!.id, tracks['t2']!.id, tracks['t3']!.id],
      );
    });
  });

  group('syncDailyAggregates', () {
    test('enqueues ONE track_stats_daily batch row keyed by the day with '
        'per-track fingerprints', () async {
      await repository.syncDailyAggregates(DateTime(2026, 6, 15));

      final rows = await db.syncOutboxDao.pending();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.tableName, 'track_stats_daily');
      expect(row.op, 'upsert');
      expect(row.rowKey, '2026-06-15');

      final payload = jsonDecode(row.payload) as Map<String, dynamic>;
      expect(payload['day'], '2026-06-15');
      final entries = (payload['entries'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(entries, hasLength(5)); // t1, t2, t3, t6, t8 played today

      // Today's aggregates: t1 10 plays / 600 s, t8 4 plays / 20 s …
      final byFingerprint = <String, Map<String, dynamic>>{
        for (final entry in entries) entry['fingerprint'] as String: entry,
      };
      final t1Entry = byFingerprint[playFingerprint(tracks['t1']!)]!;
      expect(t1Entry['plays'], 10);
      expect(t1Entry['listened_ms'], 600000);
      final t8Entry = byFingerprint[playFingerprint(tracks['t8']!)]!;
      expect(t8Entry['plays'], 4);
      expect(t8Entry['listened_ms'], 20000);
    });

    test('a day without plays still enqueues an empty batch (remote zeroes '
        'stay in sync)', () async {
      await repository.syncDailyAggregates(DateTime(2026, 6, 20));

      final rows = await db.syncOutboxDao.pending();
      expect(rows, hasLength(1));
      expect(rows.single.rowKey, '2026-06-20');
      final payload = jsonDecode(rows.single.payload) as Map<String, dynamic>;
      expect(payload['entries'], isEmpty);
    });
  });
}

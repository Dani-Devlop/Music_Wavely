/// Authored, awaiting local run.
///
/// No Flutter/Dart SDK exists in the authoring sandbox, so this suite has
/// never been executed. It targets the real `PlaysDao` API in `lib/` and
/// needs `dart run build_runner build` first (generates `app_database.g.dart`
/// and the DAO mixins).
///
/// Note: the `plays` table has NO (user, fingerprint, started_at) dedupe
/// key — `PlayRecorder` writes one row per started session and the sync
/// layer de-duplicates remotely. These tests cover the DAO exactly as it
/// exists (insertPlay / playsForTrack / totalListenedMs / topTracks /
/// incrementTrackPlayStats + the tracks FK cascade).
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavely/data/local/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<int> insertTrack(String title) {
    return db.tracksDao.insertTrack(
      TracksCompanion.insert(
        sourceId: 'local',
        sourceTrackId: 'hash-$title',
        title: title,
        artist: 'Aura',
        durationMs: 1000,
        format: 'mp3',
        addedAt: DateTime(2024),
        updatedAt: DateTime(2024),
      ),
    );
  }

  Future<int> insertPlay(
    int trackId, {
    required DateTime startedAt,
    int listenedMs = 1000,
    String deviceId = 'device-1',
  }) {
    return db.playsDao.insertPlay(
      PlaysCompanion.insert(
        trackId: trackId,
        startedAt: startedAt,
        listenedMs: listenedMs,
        source: 'local',
        deviceId: deviceId,
      ),
    );
  }

  test('insertPlay stores the session; completed defaults to false',
      () async {
    final trackId = await insertTrack('T1');
    final startedAt = DateTime(2024, 1, 2, 3);

    final playId = await insertPlay(
      trackId,
      startedAt: startedAt,
      listenedMs: 2500,
      deviceId: 'dev-9',
    );

    final row = await (db.select(db.plays)
          ..where((p) => p.id.equals(playId)))
        .getSingle();
    expect(row.trackId, trackId);
    expect(row.startedAt, startedAt);
    expect(row.listenedMs, 2500);
    expect(row.source, 'local');
    expect(row.deviceId, 'dev-9');
    expect(row.completed, isFalse, reason: 'column default');
  });

  test('an explicitly completed play roundtrips', () async {
    final trackId = await insertTrack('T1');
    await db.playsDao.insertPlay(
      PlaysCompanion.insert(
        trackId: trackId,
        startedAt: DateTime(2024, 1, 2),
        listenedMs: 1,
        completed: const Value(true),
        source: 'local',
        deviceId: 'device-1',
      ),
    );

    final row = await db.select(db.plays).getSingle();

    expect(row.completed, isTrue);
  });

  test('playsForTrack returns only that track, newest first', () async {
    final t1 = await insertTrack('T1');
    final t2 = await insertTrack('T2');
    await insertPlay(t1, startedAt: DateTime(2024, 1, 1));
    await insertPlay(t1, startedAt: DateTime(2024, 1, 3));
    await insertPlay(t1, startedAt: DateTime(2024, 1, 2));
    await insertPlay(t2, startedAt: DateTime(2024, 1, 4));

    final plays = await db.playsDao.playsForTrack(t1);

    expect(plays.map((p) => p.startedAt), [
      DateTime(2024, 1, 3),
      DateTime(2024, 1, 2),
      DateTime(2024, 1, 1),
    ]);
    expect(plays.every((p) => p.trackId == t1), isTrue);
  });

  test('totalListenedMs is 0 on an empty history and sums otherwise',
      () async {
    expect(await db.playsDao.totalListenedMs(), 0);

    final t1 = await insertTrack('T1');
    await insertPlay(t1, startedAt: DateTime(2024, 1, 1), listenedMs: 1000);
    await insertPlay(t1, startedAt: DateTime(2024, 1, 2), listenedMs: 2500);
    await insertPlay(t1, startedAt: DateTime(2024, 1, 3), listenedMs: 400);

    expect(await db.playsDao.totalListenedMs(), 3900);
  });

  test('topTracks orders by play count desc, ties by track id asc',
      () async {
    final t1 = await insertTrack('T1');
    final t2 = await insertTrack('T2');
    final t3 = await insertTrack('T3');
    for (var i = 0; i < 3; i++) {
      await insertPlay(t1, startedAt: DateTime(2024, 1, 1, i));
      await insertPlay(t2, startedAt: DateTime(2024, 1, 2, i));
    }
    await insertPlay(t3, startedAt: DateTime(2024, 1, 3));

    final top = await db.playsDao.topTracks();

    expect(top.map((t) => t.id), [t1, t2, t3]);

    final top2 = await db.playsDao.topTracks(limit: 2);
    expect(top2.map((t) => t.id), [t1, t2]);
  });

  test('topTracks is empty before any play is recorded', () async {
    await insertTrack('T1');

    expect(await db.playsDao.topTracks(), isEmpty);
  });

  test('incrementTrackPlayStats bumps playCount and stamps lastPlayedAt',
      () async {
    final trackId = await insertTrack('T1');
    expect((await db.tracksDao.getById(trackId))!.playCount, 0);
    expect((await db.tracksDao.getById(trackId))!.lastPlayedAt, isNull);

    await db.playsDao.incrementTrackPlayStats(trackId);
    final once = await db.tracksDao.getById(trackId);
    expect(once!.playCount, 1);
    expect(once.lastPlayedAt, isNotNull);
    final firstStamp = once.lastPlayedAt!;

    await db.playsDao.incrementTrackPlayStats(trackId);
    final twice = await db.tracksDao.getById(trackId);
    expect(twice!.playCount, 2);
    expect(twice.lastPlayedAt!.isBefore(firstStamp), isFalse);
  });

  test('deleting a track cascades to its plays (FK onDelete: cascade)',
      () async {
    final trackId = await insertTrack('T1');
    await insertPlay(trackId, startedAt: DateTime(2024, 1, 1));
    await insertPlay(trackId, startedAt: DateTime(2024, 1, 2));
    expect(await db.playsDao.totalListenedMs(), 2000);

    await (db.delete(db.tracks)..where((t) => t.id.equals(trackId))).go();

    expect(await db.playsDao.playsForTrack(trackId), isEmpty);
    expect(await db.playsDao.totalListenedMs(), 0);
  });
}

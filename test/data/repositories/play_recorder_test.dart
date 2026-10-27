// authored, awaiting local run.
//
// PlayRecorder tests (`lib/data/repositories/play_recorder.dart`) over an
// in-memory Drift database. Covers: the happy path (one `plays` row per
// started track with the right trackId/source/deviceId/listenedMs/
// completed fields), the null-id skip (unpersisted tracks have no foreign
// key), repeated records appending rows, the default deviceId passthrough
// and an explicit failure-contract test: record() itself does NOT swallow
// DAO failures — that guard lives in QueueManager's onTrackStarted wrapper
// (covered in test/playback/queue_manager_test.dart), which is why this
// file asserts propagation instead of non-propagation.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/utils/platform_utils.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/repositories/play_recorder.dart';
import 'package:wavely/domain/entities/entities.dart';

Track _track(int id, {String sourceId = Track.localSourceId}) => Track(
      id: id,
      sourceId: sourceId,
      sourceTrackId: 'src-$id',
      title: 'Track $id',
      artist: 'Artist',
      durationMs: 60000,
      format: 'mp3',
      filePath: '/audio/$id.mp3',
      addedAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

Future<int> _insertTrack(AppDatabase database, int id) =>
    database.tracksDao.insertTrack(
      TracksCompanion.insert(
        sourceId: Track.localSourceId,
        sourceTrackId: 'src-$id',
        title: 'Track $id',
        artist: 'Artist',
        durationMs: 60000,
        format: 'mp3',
        addedAt: DateTime(2024),
        updatedAt: DateTime(2024),
      ),
    );

Future<int> _playsCount(AppDatabase database) async {
  final row = await database
      .customSelect('SELECT COUNT(*) AS c FROM plays')
      .getSingle();
  return row.read<int>('c');
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('PlayRecorder', () {
    test('record writes one plays row for a persisted track', () async {
      final trackId = await _insertTrack(db, 1);
      final recorder = PlayRecorder(db.playsDao, deviceId: 'test-device');

      final before = DateTime.now().subtract(const Duration(minutes: 1));
      await recorder.record(_track(trackId));
      final after = DateTime.now().add(const Duration(minutes: 1));

      final plays = await db.playsDao.playsForTrack(trackId);
      expect(plays, hasLength(1));
      final play = plays.single;
      expect(play.trackId, trackId);
      expect(play.source, Track.localSourceId);
      expect(play.deviceId, 'test-device');
      expect(play.listenedMs, 0);
      expect(play.completed, isFalse);
      expect(play.startedAt.isAfter(before), isTrue);
      expect(play.startedAt.isBefore(after), isTrue);
    });

    test('record skips tracks without a database id', () async {
      final recorder = PlayRecorder(db.playsDao, deviceId: 'test-device');
      final unpersisted = _track(0).copyWith(id: null);

      await recorder.record(unpersisted);

      expect(await _playsCount(db), 0);
      expect(await db.playsDao.totalListenedMs(), 0);
    });

    test('repeated records append one row each', () async {
      final trackId = await _insertTrack(db, 1);
      final recorder = PlayRecorder(db.playsDao, deviceId: 'test-device');

      await recorder.record(_track(trackId));
      await recorder.record(_track(trackId));

      expect(await db.playsDao.playsForTrack(trackId), hasLength(2));
    });

    test('deviceId defaults to the current target platform name', () async {
      final trackId = await _insertTrack(db, 1);
      final recorder = PlayRecorder(db.playsDao);

      await recorder.record(_track(trackId));

      final play = (await db.playsDao.playsForTrack(trackId)).single;
      expect(play.deviceId, PlatformUtils.currentTargetPlatform.name);
    });

    test('the track source is mirrored into the plays row', () async {
      final localId = await _insertTrack(db, 1);
      final recorder = PlayRecorder(db.playsDao, deviceId: 'test-device');

      // A remote track row must exist before recording (FK on track id).
      await db.tracksDao.insertTrack(
        TracksCompanion.insert(
          sourceId: 'spotify',
          sourceTrackId: 'spotify-1',
          title: 'Remote Track',
          artist: 'Remote Artist',
          durationMs: 90000,
          format: 'mp3',
          addedAt: DateTime(2024),
          updatedAt: DateTime(2024),
        ),
      );

      await recorder.record(_track(localId));
      await recorder.record(_track(2, sourceId: 'spotify'));

      final plays = await db.playsDao.playsForTrack(2);
      expect(plays, hasLength(1));
      expect(plays.single.source, 'spotify');
      expect((await db.playsDao.playsForTrack(localId)).single.source,
          Track.localSourceId);
    });
  });

  group('failure contract', () {
    test('DAO failures propagate (QueueManager guards the hook instead)',
        () async {
      // A dedicated database, closed immediately: any DAO operation now
      // fails. record() has no try/catch by design — the QueueManager
      // wraps onTrackStarted in its own guard, so a recorder crash can
      // never break playback (asserted in queue_manager_test.dart).
      final local = AppDatabase(NativeDatabase.memory());
      final recorder = PlayRecorder(local.playsDao, deviceId: 'test-device');
      final track = _track(1);
      await local.close();

      Object? failure;
      try {
        await recorder.record(track);
      } on Object catch (e) {
        failure = e;
      }
      expect(failure, isNotNull,
          reason: 'record() is best-effort-by-caller, not fail-safe');
    });
  });
}

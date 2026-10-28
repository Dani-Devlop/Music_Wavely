// authored, awaiting local run.
//
// Tests for lib/data/local/db/daos/downloads_dao.dart over an in-memory
// AppDatabase (schemaVersion 3 creates the downloads table + status index
// on onCreate): enqueue, pending ordering, watchByStatuses, progress
// updates, markStatus transitions, resetInterrupted and clearFinished.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/tables/downloads.dart';

AppDatabase _db() => AppDatabase(NativeDatabase.memory());

DownloadsCompanion _row({
  String sourceId = 'jamendo',
  String sourceTrackId = 'tr-1',
  String targetPath = '/base/Music/Unknown/Unknown/Unknown/original/tr-1.mp3',
  DownloadStatus status = DownloadStatus.queued,
  int progress = 0,
  int startedOffsetSec = 0,
}) =>
    DownloadsCompanion.insert(
      sourceId: sourceId,
      sourceTrackId: sourceTrackId,
      targetPath: targetPath,
      quality: 'original',
      status: Value(status),
      progress: Value(progress),
      startedAt: DateTime.utc(2024, 1, 1, 12, startedOffsetSec),
    );

void main() {
  late AppDatabase db;

  setUp(() {
    db = _db();
  });

  tearDown(() => db.close());

  group('DownloadsDao', () {
    test('enqueue + byId round trip', () async {
      final int id = await db.downloadsDao.enqueue(_row());
      final DownloadRow? row = await db.downloadsDao.byId(id);
      expect(row, isNotNull);
      expect(row!.sourceId, 'jamendo');
      expect(row.sourceTrackId, 'tr-1');
      expect(row.quality, 'original');
      expect(row.status, DownloadStatus.queued);
      expect(row.progress, 0);
      expect(row.errorMessage, isNull);
      expect(row.completedAt, isNull);
      expect(row.provenanceJson, isNull);
    });

    test('pending returns only queued rows oldest-first', () async {
      final int a = await db.downloadsDao.enqueue(
        _row(sourceTrackId: 'a', startedOffsetSec: 10),
      );
      await db.downloadsDao.enqueue(
        _row(sourceTrackId: 'b', startedOffsetSec: 5),
      );
      await db.downloadsDao.enqueue(
        _row(
          sourceTrackId: 'c',
          startedOffsetSec: 1,
          status: DownloadStatus.completed,
        ),
      );
      final List<DownloadRow> pending = await db.downloadsDao.pending();
      expect(pending.map((DownloadRow r) => r.sourceTrackId), <String>['b', 'a']);
      expect(pending.first.id, isNot(a));
    });

    test('byStatuses and watchByStatuses filter correctly', () async {
      await db.downloadsDao.enqueue(
        _row(sourceTrackId: 'a', status: DownloadStatus.downloading),
      );
      await db.downloadsDao.enqueue(
        _row(sourceTrackId: 'b', status: DownloadStatus.failed),
      );
      await db.downloadsDao.enqueue(
        _row(sourceTrackId: 'c', status: DownloadStatus.downloading),
      );
      final List<DownloadRow> active = await db.downloadsDao
          .byStatuses(<DownloadStatus>[DownloadStatus.downloading]);
      expect(active.map((DownloadRow r) => r.sourceTrackId).toSet(),
          <String>{'a', 'c'});

      final Stream<List<DownloadRow>> stream = db.downloadsDao
          .watchByStatuses(<DownloadStatus>[DownloadStatus.downloading]);
      final List<List<DownloadRow>> emissions =
          await stream.take(2).toList();
      expect(emissions.first, hasLength(2));
    });

    test('updateProgress clamps to 0–100', () async {
      final int id = await db.downloadsDao.enqueue(_row());
      await db.downloadsDao.updateProgress(id, 150);
      expect((await db.downloadsDao.byId(id))!.progress, 100);
      await db.downloadsDao.updateProgress(id, -5);
      expect((await db.downloadsDao.byId(id))!.progress, 0);
      await db.downloadsDao.updateProgress(id, 42);
      expect((await db.downloadsDao.byId(id))!.progress, 42);
    });

    test('markStatus writes status, error, completion and provenance',
        () async {
      final int id = await db.downloadsDao.enqueue(_row());
      final DateTime done = DateTime.utc(2024, 1, 2);
      await db.downloadsDao.markStatus(
        id,
        DownloadStatus.completed,
        completedAt: done,
        provenanceJson: '{"source":"jamendo"}',
      );
      final DownloadRow row = (await db.downloadsDao.byId(id))!;
      expect(row.status, DownloadStatus.completed);
      expect(row.completedAt, done);
      expect(row.provenanceJson, '{"source":"jamendo"}');

      await db.downloadsDao.markStatus(
        id,
        DownloadStatus.failed,
        errorMessage: 'boom',
      );
      final DownloadRow failed = (await db.downloadsDao.byId(id))!;
      expect(failed.status, DownloadStatus.failed);
      expect(failed.errorMessage, 'boom');
    });

    test('resetInterrupted flips downloading → queued only', () async {
      await db.downloadsDao.enqueue(
        _row(sourceTrackId: 'a', status: DownloadStatus.downloading),
      );
      await db.downloadsDao.enqueue(
        _row(sourceTrackId: 'b', status: DownloadStatus.downloading),
      );
      await db.downloadsDao.enqueue(
        _row(sourceTrackId: 'c', status: DownloadStatus.failed),
      );
      final int changed = await db.downloadsDao.resetInterrupted();
      expect(changed, 2);
      expect((await db.downloadsDao.pending()).length, 2);
    });

    test('clearFinished removes completed + canceled rows only', () async {
      await db.downloadsDao.enqueue(
        _row(sourceTrackId: 'a', status: DownloadStatus.completed),
      );
      await db.downloadsDao.enqueue(
        _row(sourceTrackId: 'b', status: DownloadStatus.canceled),
      );
      await db.downloadsDao.enqueue(
        _row(sourceTrackId: 'c', status: DownloadStatus.failed),
      );
      final int removed = await db.downloadsDao.clearFinished();
      expect(removed, 2);
      final List<DownloadRow> left =
          await db.downloadsDao.byStatuses(DownloadStatus.values);
      expect(left.single.sourceTrackId, 'c');
    });

    test('schema: unique row ids auto-increment and timestamps persist',
        () async {
      final int a = await db.downloadsDao.enqueue(
        _row(startedOffsetSec: 1),
      );
      final int b = await db.downloadsDao.enqueue(
        _row(startedOffsetSec: 2),
      );
      expect(b, greaterThan(a));
      final DownloadRow row = (await db.downloadsDao.byId(b))!;
      expect(row.startedAt, DateTime.utc(2024, 1, 1, 12, 2));
    });
  });
}

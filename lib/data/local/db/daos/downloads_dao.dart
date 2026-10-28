import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/tables/downloads.dart';

part 'downloads_dao.g.dart';

/// Persistence for the download manager (Stage 2.1 Section 9).
@DriftAccessor(tables: [Downloads])
class DownloadsDao extends DatabaseAccessor<AppDatabase>
    with _$DownloadsDaoMixin {
  DownloadsDao(super.attachedDatabase);

  /// Inserts a queued job; returns the generated row id.
  Future<int> enqueue(DownloadsCompanion entry) =>
      into(downloads).insert(entry);

  /// One job by id.
  Future<DownloadRow?> byId(int id) =>
      (select(downloads)..where((d) => d.id.equals(id))).getSingleOrNull();

  /// Queued jobs oldest-first (the queue the service pumps from).
  Future<List<DownloadRow>> pending() =>
      (select(downloads)
            ..where((d) => d.status.equals(DownloadStatus.queued.name))
            ..orderBy([(d) => OrderingTerm.asc(d.startedAt)]))
          .get();

  /// Jobs whose status is in [statuses].
  Future<List<DownloadRow>> byStatuses(List<DownloadStatus> statuses) =>
      (select(downloads)
            ..where(
              (d) => d.status.isIn(
                statuses.map((DownloadStatus s) => s.name).toList(),
              ),
            )
            ..orderBy([(d) => OrderingTerm.desc(d.startedAt)]))
          .get();

  /// Stage 3 audit (BUG-5): an existing queued/active row for the same
  /// source track, used to dedupe concurrent enqueues of one file.
  Future<DownloadRow?> activeForSourceTrack(
    String sourceId,
    String sourceTrackId,
  ) =>
      (select(downloads)
            ..where((d) => d.sourceId.equals(sourceId))
            ..where((d) => d.sourceTrackId.equals(sourceTrackId))
            ..where(
              (d) => d.status.isIn(
                const [DownloadStatus.queued, DownloadStatus.downloading]
                    .map((DownloadStatus s) => s.name)
                    .toList(),
              ),
            )
            ..limit(1))
          .getSingleOrNull();

  /// Live query for the downloads screen sections.
  Stream<List<DownloadRow>> watchByStatuses(List<DownloadStatus> statuses) =>
      (select(downloads)
            ..where(
              (d) => d.status.isIn(
                statuses.map((DownloadStatus s) => s.name).toList(),
              ),
            )
            ..orderBy([(d) => OrderingTerm.desc(d.startedAt)]))
          .watch();

  /// Updates the progress percentage of [id].
  Future<void> updateProgress(int id, int progress) =>
      (update(downloads)..where((d) => d.id.equals(id)))
          .write(DownloadsCompanion(progress: Value(progress.clamp(0, 100))));

  /// Sets the status and optional error / completion / provenance fields.
  Future<void> markStatus(
    int id,
    DownloadStatus status, {
    String? errorMessage,
    DateTime? completedAt,
    String? provenanceJson,
  }) =>
      (update(downloads)..where((d) => d.id.equals(id))).write(
        DownloadsCompanion(
          status: Value(status),
          errorMessage: Value(errorMessage),
          completedAt: Value(completedAt),
          provenanceJson: Value(provenanceJson),
        ),
      );

  /// Boot-time repair: jobs left in `downloading` by a crash go back to the
  /// queue (partial files resume via HTTP Range).
  Future<int> resetInterrupted() =>
      (update(downloads)..where((d) => d.status.equals(DownloadStatus.downloading.name)))
          .write(DownloadsCompanion(status: Value(DownloadStatus.queued)));

  /// Removes finished (completed / canceled) jobs from the list.
  Future<int> clearFinished() =>
      (delete(downloads)..where(
        (d) => d.status.isIn(<String>[
          DownloadStatus.completed.name,
          DownloadStatus.canceled.name,
        ]),
      )).go();
}

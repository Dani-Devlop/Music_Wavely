import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/tables/tracks.dart';

/// Lifecycle of one download job (Stage 2.1 Section 9).
enum DownloadStatus { queued, downloading, completed, failed, canceled }

/// Persisted download jobs. `trackId` is nullable because online-only
/// tracks are not in the local library; `provenanceJson` mirrors the
/// sidecar written next to the file.
@DataClassName('DownloadRow', companion: 'DownloadsCompanion')
@TableIndex(name: 'idx_downloads_status', columns: {#status})
class Downloads extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Local library track when present (online-only jobs leave this null).
  IntColumn get trackId => integer().nullable().references(Tracks, #id)();

  TextColumn get sourceId => text()();

  TextColumn get sourceTrackId => text()();

  /// Absolute path of the target file (io platforms only).
  TextColumn get targetPath => text()();

  /// Requested quality: `320` | `flac` | `original`.
  TextColumn get quality => text()();

  TextEnum<DownloadStatus> get status => textEnum<DownloadStatus>()();

  /// 0–100 percent.
  IntColumn get progress => integer()();

  TextColumn get errorMessage => text().nullable()();

  DateTimeColumn get startedAt => dateTime()();

  DateTimeColumn get completedAt => dateTime().nullable()();

  /// JSON blob identical to the `<trackId>.wavely.json` sidecar.
  TextColumn get provenanceJson => text().nullable()();
}

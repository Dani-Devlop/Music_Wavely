import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/tables/tracks.dart';

/// Lifecycle of one download job (Stage 2.1 Section 9).
enum DownloadStatus { queued, downloading, completed, failed, canceled }

/// Stores DateTimes as unix-epoch **seconds** (identical wire format to
/// Drift's default dateTime() column) but reads them back as UTC, so a
/// `DateTime.utc(...)` written via enqueue/markStatus round-trips with its
/// UTC flag intact instead of degrading to local time.
class UtcDateTimeConverter extends TypeConverter<DateTime, int> {
  /// Const constructor for const column definitions.
  const UtcDateTimeConverter();

  @override
  DateTime fromSql(int secondsSinceEpoch) =>
      DateTime.fromMillisecondsSinceEpoch(secondsSinceEpoch * 1000,
          isUtc: true);

  @override
  int toSql(DateTime value) => value.millisecondsSinceEpoch ~/ 1000;
}

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

  TextColumn get status => textEnum<DownloadStatus>()();

  /// 0–100 percent.
  IntColumn get progress => integer()();

  TextColumn get errorMessage => text().nullable()();

  DateTimeColumn get startedAt => dateTime().map(const UtcDateTimeConverter())();

  DateTimeColumn get completedAt =>
      dateTime().nullable().map(const UtcDateTimeConverter())();

  /// JSON blob identical to the `<trackId>.wavely.json` sidecar.
  TextColumn get provenanceJson => text().nullable()();
}

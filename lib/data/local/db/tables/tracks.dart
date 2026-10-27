import 'package:drift/drift.dart';

/// Local + remote tracks table; the primary library store.
///
/// `sourceId` + `sourceTrackId` form the cross-run identity of a track (the
/// scanner hashes `path:size:mtime` into `sourceTrackId` for local files).
/// `playCount` / `lastPlayedAt` are playback stats maintained by
/// `PlaysDao.incrementTrackPlayStats`.
@DataClassName('TracksRow', companion: 'TracksCompanion')
@TableIndex(
  name: 'idx_tracks_source',
  columns: {#sourceId, #sourceTrackId},
  unique: true,
)
@TableIndex(name: 'idx_tracks_title', columns: {#title})
@TableIndex(name: 'idx_tracks_artist', columns: {#artist})
class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get sourceId => text()();

  TextColumn get sourceTrackId => text()();

  TextColumn get title => text()();

  TextColumn get artist => text()();

  TextColumn get album => text().nullable()();

  TextColumn get genre => text().nullable()();

  TextColumn get language => text().nullable()();

  IntColumn get durationMs => integer()();

  /// Kilobits per second; null when the container does not report one.
  IntColumn get bitrate => integer().nullable()();

  TextColumn get format => text()();

  TextColumn get filePath => text().nullable()();

  TextColumn get coverPath => text().nullable()();

  BoolColumn get explicit => boolean().withDefault(const Constant(false))();

  DateTimeColumn get addedAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  IntColumn get playCount => integer().withDefault(const Constant(0))();

  DateTimeColumn get lastPlayedAt => dateTime().nullable()();
}

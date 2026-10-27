import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/tables/tracks.dart';

/// One listening session of a track (playback engine writes these).
///
/// `source` mirrors the track `sourceId` (e.g. `local`) and `deviceId` is the
/// stable per-install identifier used for stats.
@DataClassName('PlayRow', companion: 'PlaysCompanion')
@TableIndex(name: 'idx_plays_track', columns: {#trackId})
@TableIndex(name: 'idx_plays_started', columns: {#startedAt})
class Plays extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get trackId => integer().references(
        Tracks,
        #id,
        onDelete: KeyAction.cascade,
      )();

  DateTimeColumn get startedAt => dateTime()();

  IntColumn get listenedMs => integer()();

  BoolColumn get completed => boolean().withDefault(const Constant(false))();

  TextColumn get source => text()();

  TextColumn get deviceId => text()();
}

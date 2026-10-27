import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/tables/tracks.dart';

/// Tracks the user liked; one row per track (unique [trackId]).
@DataClassName('LikedTrackRow', companion: 'LikedTracksCompanion')
class LikedTracks extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get trackId => integer().unique().references(
        Tracks,
        #id,
        onDelete: KeyAction.cascade,
      )();

  DateTimeColumn get addedAt => dateTime()();
}

import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/tables/playlists.dart';
import 'package:wavely/data/local/db/tables/tracks.dart';

/// Ordered membership rows of [Playlists].
///
/// Deleting a playlist or a track cascades; the unique index prevents the
/// same track from appearing twice in one playlist (re-adding it should
/// instead bump [position] / `addedAt`).
@DataClassName('PlaylistItemRow', companion: 'PlaylistItemsCompanion')
@TableIndex(
  name: 'idx_playlist_items_unique',
  columns: {#playlistId, #trackId},
  unique: true,
)
class PlaylistItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get playlistId => integer().references(
        Playlists,
        #id,
        onDelete: KeyAction.cascade,
        onUpdate: KeyAction.cascade,
      )();

  IntColumn get trackId => integer().references(
        Tracks,
        #id,
        onDelete: KeyAction.cascade,
      )();

  IntColumn get position => integer()();

  DateTimeColumn get addedAt => dateTime()();
}

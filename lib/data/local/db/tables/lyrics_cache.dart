import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/tables/tracks.dart';

/// Cached lyrics per track and provider (`embedded`, `lrclib`, ...).
///
/// `syncedLrc` holds raw LRC text (possibly with word-level tags) and
/// `plainText` holds unsynced text; the lyrics feature's parser turns these
/// into [LyricsResult]. One row per (track, provider) via the unique index.
@DataClassName('LyricsCacheRow', companion: 'LyricsCacheCompanion')
@TableIndex(
  name: 'idx_lyrics_cache_track_provider',
  columns: {#trackId, #provider},
  unique: true,
)
class LyricsCache extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get trackId => integer().references(
        Tracks,
        #id,
        onDelete: KeyAction.cascade,
      )();

  TextColumn get provider => text()();

  TextColumn get syncedLrc => text().nullable()();

  TextColumn get plainText => text().nullable()();

  /// Manual sync offset in milliseconds applied by the lyrics view.
  IntColumn get offsetMs => integer().withDefault(const Constant(0))();

  DateTimeColumn get fetchedAt => dateTime()();
}

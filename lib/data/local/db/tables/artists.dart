import 'package:drift/drift.dart';

/// Artist projection table maintained by the scanner post-pass.
///
/// The scanner recomputes track/album counts from `tracks` after each run.
/// The unique index keeps one row per name; comparisons elsewhere use
/// `COLLATE NOCASE` so casing variants still resolve to this row.
@DataClassName('ArtistRow', companion: 'ArtistsCompanion')
@TableIndex(name: 'idx_artists_name', columns: {#name}, unique: true)
class Artists extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  TextColumn get coverPath => text().nullable()();

  IntColumn get trackCount => integer().withDefault(const Constant(0))();

  IntColumn get albumCount => integer().withDefault(const Constant(0))();
}

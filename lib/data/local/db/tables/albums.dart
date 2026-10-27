import 'package:drift/drift.dart';

/// Album projection table maintained by the scanner post-pass.
///
/// The scanner recomputes track counts from `tracks` after each run; `key`
/// is `'${artist.toLowerCase()}::${title.toLowerCase()}'` so case variants
/// of the same album collapse into one row.
@DataClassName('AlbumRow', companion: 'AlbumsCompanion')
@TableIndex(name: 'idx_albums_key', columns: {#key}, unique: true)
class Albums extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get key => text()();

  TextColumn get title => text()();

  TextColumn get artist => text()();

  TextColumn get coverPath => text().nullable()();

  IntColumn get year => integer().nullable()();

  DateTimeColumn get addedAt => dateTime()();

  IntColumn get trackCount => integer().withDefault(const Constant(0))();
}

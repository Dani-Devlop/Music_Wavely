import 'package:drift/drift.dart';

/// User-created playlists.
@DataClassName('PlaylistRow', companion: 'PlaylistsCompanion')
class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  TextColumn get description => text().nullable()();

  TextColumn get coverPath => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();
}

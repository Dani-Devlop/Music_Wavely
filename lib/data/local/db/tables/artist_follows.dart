import 'package:drift/drift.dart';

/// Artists the user follows for discovery ("new from followed artists",
/// Stage 1.2, B10). Local table; synced via the outbox.
@DataClassName('ArtistFollowRow', companion: 'ArtistFollowsCompanion')
class ArtistFollows extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get artistName => text().unique();

  /// MusicBrainz MBID when resolvable (drives the discovery lookup).
  TextColumn get mbid => text().nullable()();

  DateTimeColumn get followedAt => dateTime()();
}

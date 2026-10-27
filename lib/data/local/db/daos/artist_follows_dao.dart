import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/tables/artist_follows.dart';

part 'artist_follows_dao.g.dart';

/// Followed artists for the discovery feature (Stage 1.2, B10).
@DriftAccessor(tables: [ArtistFollows])
class ArtistFollowsDao extends DatabaseAccessor<AppDatabase>
    with _$ArtistFollowsDaoMixin {
  ArtistFollowsDao(super.attachedDatabase);

  Future<List<ArtistFollowRow>> all() =>
      (select(artistFollows)
            ..orderBy([(f) => OrderingTerm.desc(f.followedAt)]))
          .get();

  /// Idempotent follow (INSERT OR IGNORE on the unique artist name).
  Future<void> follow(String artistName, {String? mbid}) =>
      into(artistFollows).insert(
        ArtistFollowsCompanion.insert(
          artistName: artistName,
          mbid: Value(mbid),
          followedAt: DateTime.now(),
        ),
        mode: InsertMode.insertOrIgnore,
      );

  Future<int> unfollow(String artistName) =>
      (delete(artistFollows)..where((f) => f.artistName.equals(artistName)))
          .go();

  Future<bool> isFollowing(String artistName) async {
    final row = await (select(artistFollows)
          ..where((f) => f.artistName.equals(artistName))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }
}

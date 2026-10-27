/// Authored, awaiting local run.
///
/// No Flutter/Dart SDK exists in the authoring sandbox, so this suite has
/// never been executed. It targets the real `ArtistFollowsDao` API in
/// `lib/` and needs `dart run build_runner build` first (generates
/// `app_database.g.dart` and the DAO mixins).
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavely/data/local/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  /// Direct insert with an explicit followedAt so the ordering test stays
  /// deterministic (drift stores DateTimes with second granularity).
  Future<int> followAt(DateTime followedAt, String artistName,
      {String? mbid}) {
    return db.into(db.artistFollows).insert(
          ArtistFollowsCompanion.insert(
            artistName: artistName,
            mbid: Value(mbid),
            followedAt: followedAt,
          ),
        );
  }

  test('follow stores the artist with an optional mbid and timestamp',
      () async {
    await db.artistFollowsDao.follow('Aura');
    await db.artistFollowsDao.follow('Bo', mbid: 'mbid-123');

    expect(await db.artistFollowsDao.isFollowing('Aura'), isTrue);
    expect(await db.artistFollowsDao.isFollowing('Bo'), isTrue);

    final rows = await db.artistFollowsDao.all();
    expect(rows, hasLength(2));
    final aura = rows.singleWhere((r) => r.artistName == 'Aura');
    final bo = rows.singleWhere((r) => r.artistName == 'Bo');
    expect(aura.mbid, isNull);
    expect(bo.mbid, 'mbid-123');
    expect(aura.followedAt, isNotNull);
  });

  test('follow is idempotent on the unique artist name', () async {
    await db.artistFollowsDao.follow('Aura');
    await db.artistFollowsDao.follow('Aura', mbid: 'late-mbid');

    final rows = await db.artistFollowsDao.all();

    expect(rows, hasLength(1));
    expect(rows.single.artistName, 'Aura');
    expect(rows.single.mbid, isNull,
        reason: 'INSERT OR IGNORE keeps the first row');
  });

  test('all() lists newest follows first', () async {
    await followAt(DateTime(2024, 1, 1), 'old');
    await followAt(DateTime(2024, 3, 1), 'newest');
    await followAt(DateTime(2024, 2, 1), 'middle');

    final rows = await db.artistFollowsDao.all();

    expect(rows.map((r) => r.artistName), ['newest', 'middle', 'old']);
  });

  test('isFollowing is false for unknown or unfollowed artists', () async {
    expect(await db.artistFollowsDao.isFollowing('Nobody'), isFalse);

    await db.artistFollowsDao.follow('Aura');
    expect(await db.artistFollowsDao.isFollowing('Aura'), isTrue);
    expect(await db.artistFollowsDao.isFollowing('aura'), isFalse,
        reason: 'lookups are exact, only the PK stores the casing');
  });

  test('unfollow removes the row and reports the affected count', () async {
    await db.artistFollowsDao.follow('Aura');
    await db.artistFollowsDao.follow('Bo');

    expect(await db.artistFollowsDao.unfollow('Aura'), 1);
    expect(await db.artistFollowsDao.unfollow('Aura'), 0);

    expect(await db.artistFollowsDao.isFollowing('Aura'), isFalse);
    expect((await db.artistFollowsDao.all()).map((r) => r.artistName),
        ['Bo']);
  });

  test('all() on an empty table returns an empty list', () async {
    expect(await db.artistFollowsDao.all(), isEmpty);
  });
}

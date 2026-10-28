// authored, awaiting local run.
//
// Tests for lib/features/discovery/follow_artist.dart (+ the underlying
// lib/data/local/db/daos/artist_follows_dao.dart over a memory database):
// follow persists (with MBID, idempotent), unfollow removes, isFollowing /
// all() reflect state, the artistFollowStateProvider roundtrip through
// toggleFollow in a widget harness, and toggleFollow's never-throw contract
// against a closed database.
//
// NOTE: toggleFollow does NOT enqueue a sync-outbox row — ArtistFollowsDao
// has no outbox hook (follows sync via a later-stage path). The test below
// asserts the actual (absent) outbox behavior rather than the hinted one.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/features/discovery/follow_artist.dart';

AppDatabase _memoryDb() => AppDatabase(NativeDatabase.memory());

/// Minimal widget that watches [artistFollowStateProvider] and drives
/// [toggleFollow], mirroring the documented artist-detail wiring.
class _FollowHarness extends ConsumerStatefulWidget {
  const _FollowHarness(this.artist, {this.mbid});

  final String artist;
  final String? mbid;

  @override
  ConsumerState<_FollowHarness> createState() => _FollowHarnessState();
}

class _FollowHarnessState extends ConsumerState<_FollowHarness> {
  @override
  Widget build(BuildContext context) {
    final following = ref.watch(artistFollowStateProvider(widget.artist));
    return Scaffold(
      body: Column(
        children: <Widget>[
          following.when(
            data: (value) => Text(value ? 'following' : 'not-following'),
            loading: () => const Text('loading'),
            error: (Object error, StackTrace _) => const Text('error'),
          ),
          IconButton(
            key: const ValueKey<String>('toggle'),
            icon: const Icon(Icons.favorite),
            onPressed: () =>
                unawaited(toggleFollow(ref, widget.artist, mbid: widget.mbid)),
          ),
        ],
      ),
    );
  }
}

Widget _wrap(AppDatabase db, {required String artist, String? mbid}) =>
    ProviderScope(
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: _FollowHarness(artist, mbid: mbid),
      ),
    );

void main() {
  group('ArtistFollowsDao (memory database)', () {
    test('follow persists with mbid + timestamp; isFollowing reflects it',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final dao = db.artistFollowsDao;

      expect(await dao.isFollowing('Aurora'), isFalse);
      await dao.follow('Aurora', mbid: 'mbid-aurora');

      expect(await dao.isFollowing('Aurora'), isTrue);
      final rows = await dao.all();
      expect(rows, hasLength(1));
      expect(rows.single.artistName, 'Aurora');
      expect(rows.single.mbid, 'mbid-aurora');
      expect(rows.single.followedAt, isNotNull);
    });

    test('follow is idempotent (INSERT OR IGNORE on the unique name)',
        () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final dao = db.artistFollowsDao;

      await dao.follow('Aurora', mbid: 'mbid-a');
      await dao.follow('Aurora', mbid: 'mbid-b'); // ignored

      final rows = await dao.all();
      expect(rows, hasLength(1));
      expect(rows.single.mbid, 'mbid-a'); // the first row wins
    });

    test('unfollow removes the row', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final dao = db.artistFollowsDao;

      await dao.follow('Aurora');
      expect(await dao.unfollow('Aurora'), 1);

      expect(await dao.isFollowing('Aurora'), isFalse);
      expect(await dao.all(), isEmpty);
    });

    test('unfollowing an unknown artist removes nothing', () async {
      final db = _memoryDb();
      addTearDown(db.close);

      expect(await db.artistFollowsDao.unfollow('Nobody'), 0);
    });

    test('all() lists follows newest-first', () async {
      final db = _memoryDb();
      addTearDown(db.close);
      // Direct inserts pin followedAt so the ordering is deterministic
      // (drift stores datetimes at second precision — dao.follow calls in
      // the same second would tie).
      await db.into(db.artistFollows).insert(
            ArtistFollowsCompanion.insert(
              artistName: 'Old Follow',
              followedAt: DateTime(2026, 1, 1),
            ),
          );
      await db.into(db.artistFollows).insert(
            ArtistFollowsCompanion.insert(
              artistName: 'New Follow',
              mbid: const Value('mbid-n'),
              followedAt: DateTime(2026, 6, 15),
            ),
          );

      final rows = await db.artistFollowsDao.all();
      expect(
        [for (final row in rows) row.artistName],
        <String>['New Follow', 'Old Follow'],
      );
    });
  });

  group('toggleFollow (widget harness)', () {
    testWidgets('follow persists, invalidates the provider state and stores '
        'the mbid', (WidgetTester tester) async {
      final db = _memoryDb();
      addTearDown(db.close);

      await tester.pumpWidget(_wrap(db, artist: 'Aurora', mbid: 'mbid-a'));
      await tester.pumpAndSettle();
      expect(find.text('not-following'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('toggle')));
      await tester.pumpAndSettle();

      expect(find.text('following'), findsOneWidget);
      expect(await db.artistFollowsDao.isFollowing('Aurora'), isTrue);
      final row = (await db.artistFollowsDao.all()).single;
      expect(row.mbid, 'mbid-a');
      // No sync outbox row is written by the follow flow.
      expect(await db.syncOutboxDao.count(), 0);
    });

    testWidgets('tapping again unfollows and clears the state',
        (WidgetTester tester) async {
      final db = _memoryDb();
      addTearDown(db.close);
      await db.artistFollowsDao.follow('Aurora');

      await tester.pumpWidget(_wrap(db, artist: 'Aurora'));
      await tester.pumpAndSettle();
      expect(find.text('following'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('toggle')));
      await tester.pumpAndSettle();

      expect(find.text('not-following'), findsOneWidget);
      expect(await db.artistFollowsDao.all(), isEmpty);
    });

    testWidgets('a failed toggle never crashes the caller (closed db)',
        (WidgetTester tester) async {
      final db = _memoryDb();
      await db.close(); // every dao call from now on throws

      await tester.pumpWidget(_wrap(db, artist: 'Aurora'));
      await tester.pumpAndSettle();
      // The provider surfaces the storage error as an error state.
      expect(find.text('error'), findsOneWidget);

      // The tap itself must not throw an unhandled exception.
      await tester.tap(find.byKey(const ValueKey<String>('toggle')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}

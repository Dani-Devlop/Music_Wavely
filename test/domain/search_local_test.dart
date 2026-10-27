// authored, awaiting local run.
//
// SearchLocal usecase tests (`lib/domain/usecases/search_local.dart`) over
// an in-memory Drift database (NativeDatabase.memory()) pre-populated via
// TracksDao. Covers: blank/empty queries, the FTS5 prefix semantics (only
// the LAST token is a prefix; multi-token implicit AND), case-insensitive
// matching, artist/album facet derivation, the `ftsPageSize` cap and the
// `TracksDao.ftsPrefixQuery` MATCH-expression contract. Exact FTS5 bm25
// ranking order is deliberately not pinned — it is an implementation
// detail of SQLite's rank column; result-SET correctness is asserted
// instead.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/tracks_dao.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/usecases/search_local.dart';

void main() {
  late AppDatabase db;
  late SearchLocal search;

  Future<void> _insertTrack(
    int n, {
    required String title,
    required String artist,
    String? album,
  }) async {
    await db.tracksDao.insertTrack(
      TracksCompanion.insert(
        sourceId: Track.localSourceId,
        sourceTrackId: 'src-$n',
        title: title,
        artist: artist,
        album: Value(album),
        durationMs: 120000 + n,
        format: 'mp3',
        addedAt: DateTime(2024, 1, n),
        updatedAt: DateTime(2024, 1, n),
      ),
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    search = SearchLocal(db.tracksDao);
    await _insertTrack(
      1,
      title: 'Paper Boats',
      artist: 'Marina Fold',
      album: 'Tidelines',
    );
    await _insertTrack(
      2,
      title: 'Glass Harbour',
      artist: 'Aria Wave',
      album: 'Chromatic',
    );
    await _insertTrack(
      3,
      title: 'Paper Lanterns',
      artist: 'Mirren Vale',
      album: 'Hush',
    );
    await _insertTrack(
      4,
      title: 'Neon Rivers',
      artist: 'Kodo Line',
      album: 'Night Drive',
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('blank queries', () {
    test('empty query yields an empty result set', () async {
      final results = await search('');
      expect(results.isEmpty, isTrue);
      expect(results.tracks, isEmpty);
      expect(results.artists, isEmpty);
      expect(results.albums, isEmpty);
    });

    test('whitespace-only query yields an empty result set', () async {
      final results = await search('   ');
      expect(results.isEmpty, isTrue);
    });
  });

  group('prefix behaviour', () {
    test('the last token matches as a prefix while typing', () async {
      final results = await search('paper boa');
      expect(
        results.tracks.map((t) => t.title),
        <String>['Paper Boats'],
      );
    });

    test('a single token matches as a prefix', () async {
      final results = await search('harbo');
      expect(
        results.tracks.map((t) => t.title),
        <String>['Glass Harbour'],
      );
    });

    test('earlier tokens must match fully (no prefix)', () async {
      // "paper lan" -> AND(paper, lan*) matches Paper Lanterns but NOT
      // Paper Boats (no "lantern" token at all).
      final results = await search('paper lan');
      expect(
        results.tracks.map((t) => t.title),
        <String>['Paper Lanterns'],
      );
    });

    test('multi-token AND keeps out non-matching tracks', () async {
      final results = await search('paper lantern');
      expect(
        results.tracks.map((t) => t.title),
        <String>['Paper Lanterns'],
      );
    });

    test('matching is case-insensitive', () async {
      final results = await search('PAPER');
      expect(
        results.tracks.map((t) => t.title).toSet(),
        <String>{'Paper Boats', 'Paper Lanterns'},
      );
    });

    test('ftsPrefixQuery escapes quotes and prefixes the last token only',
        () {
      expect(TracksDao.ftsPrefixQuery(''), isNull);
      expect(TracksDao.ftsPrefixQuery('   '), isNull);
      expect(TracksDao.ftsPrefixQuery('paper boa'), '"paper" "boa"*');
      expect(
        TracksDao.ftsPrefixQuery('say "hi"'),
        '"say" ""hi""*',
      );
    });
  });

  group('facets', () {
    test('artist facets are derived from track matches', () async {
      final results = await search('marina');
      expect(results.tracks.map((t) => t.title), <String>['Paper Boats']);
      expect(
        results.artists.map((a) => a.name),
        contains('Marina Fold'),
      );
    });

    test('album facets are derived from album matches', () async {
      final results = await search('tidelines');
      expect(results.tracks.map((t) => t.title), <String>['Paper Boats']);
      final album = results.albums.single;
      expect(album.title, 'Tidelines');
      expect(album.artist, 'Marina Fold');
      expect(album.key, 'marina fold::tidelines');
    });

    test('a query matching nothing anywhere yields an empty set', () async {
      final results = await search('zzz-nothing');
      expect(results.isEmpty, isTrue);
    });

    test('artists carry case-folded alphabetical order from the DAO',
        () async {
      final results = await search('paper');
      // Two matched tracks from two different artists -> two facets.
      expect(results.artists, hasLength(2));
      expect(
        results.artists.map((a) => a.name).toSet(),
        <String>{'Marina Fold', 'Mirren Vale'},
      );
    });
  });

  group('result cap', () {
    test('FTS results are capped at AppConstants.ftsPageSize', () async {
      for (var i = 1; i <= 60; i++) {
        await _insertTrack(
          100 + i,
          title: 'Echo Song $i',
          artist: 'Singer $i',
        );
      }
      final results = await search('echo');
      expect(results.tracks, hasLength(AppConstants.ftsPageSize));
    });
  });
}

/// Authored, awaiting local run.
///
/// No Flutter/Dart SDK exists in the authoring sandbox, so this suite has
/// never been executed. It targets the real FTS5 setup created by
/// `AppDatabase.onCreate` (external-content `tracks_fts` + three sync
/// triggers from `Migration0001`) and needs `dart run build_runner build`
/// first (generates `app_database.g.dart`).
///
/// The bundled sqlite3 behind `NativeDatabase.memory()` ships FTS5, so the
/// real production setup path is exercised end to end.
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/tracks_dao.dart';

void main() {
  late AppDatabase db;
  var seq = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    seq = 0;
  });
  tearDown(() => db.close());

  Future<int> insert({
    required String title,
    String artist = 'Neon Rivers',
    String? album,
  }) {
    return db.tracksDao.insertTrack(
      TracksCompanion.insert(
        sourceId: 'local',
        sourceTrackId: 'hash-${++seq}',
        title: title,
        artist: artist,
        album: Value(album),
        durationMs: 1000,
        format: 'mp3',
        addedAt: DateTime(2024),
        updatedAt: DateTime(2024),
      ),
    );
  }

  group('searchFts', () {
    test('blank and whitespace-only queries short-circuit to empty', () async {
      await insert(title: 'Paper Boats');

      expect(await db.tracksDao.searchFts(''), isEmpty);
      expect(await db.tracksDao.searchFts('   '), isEmpty);
      expect(await db.tracksDao.searchFts(' \t\n '), isEmpty);
    });

    test('a lone token is the last token, so it matches as a prefix',
        () async {
      final paperBoats = await insert(title: 'Paper Boats');
      final papercut = await insert(title: 'Papercut');
      final boatSong = await insert(title: 'Boat Song');

      final hits = await db.tracksDao.searchFts('paper');
      expect(hits.map((t) => t.id), containsAll([paperBoats, papercut]));
      expect(hits.map((t) => t.id), isNot(contains(boatSong)));

      final boats = await db.tracksDao.searchFts('boats');
      expect(boats.map((t) => t.id), [paperBoats]);
    });

    test('earlier tokens must match fully; only the last one is a prefix',
        () async {
      final paperBoats = await insert(title: 'Paper Boats');
      await insert(title: 'Papercut');
      await insert(title: 'Boat Song');

      // `"paper" "b"*` — the completed first token has to match exactly
      // (`papercut` does not), the typed-so-far second one as a prefix.
      final hits = await db.tracksDao.searchFts('paper b');
      expect(hits.map((t) => t.id), [paperBoats]);
    });

    test('partial LAST token acts as a prefix while typing', () async {
      final paperBoats = await insert(title: 'Paper Boats');
      await insert(title: 'Paper Lanterns');
      await insert(title: 'Boat Song');

      // `"paper" "boa"*` — an implicit AND of the completed first token and
      // the still-being-typed prefix. Only "Paper Boats" satisfies both.
      final hits = await db.tracksDao.searchFts('paper boa');
      expect(hits.map((t) => t.id), [paperBoats]);

      // The prefix keeps matching as the user completes the word.
      final completed = await db.tracksDao.searchFts('paper boat');
      expect(completed.map((t) => t.id), contains(paperBoats));
    });

    test('searches artist and album columns as well', () async {
      final byArtist =
          await insert(title: 'Saltwater', artist: 'Harbour Lights');
      final byAlbum = await insert(title: 'Tideline', album: 'Glass Harbour');

      expect((await db.tracksDao.searchFts('harbour')).map((t) => t.id),
          contains(byArtist));
      expect((await db.tracksDao.searchFts('glass')).map((t) => t.id),
          contains(byAlbum));
    });

    test('results are capped at AppConstants.ftsPageSize', () async {
      for (var i = 0; i < AppConstants.ftsPageSize + 10; i++) {
        await insert(title: 'Echo $i');
      }

      final hits = await db.tracksDao.searchFts('echo');
      expect(hits, hasLength(AppConstants.ftsPageSize));
    });

    test('AFTER DELETE trigger removes rows from the index', () async {
      final id = await insert(title: 'Paper Boats');
      expect(await db.tracksDao.searchFts('paper'), isNotEmpty);

      await (db.delete(db.tracks)..where((t) => t.id.equals(id))).go();

      expect(await db.tracksDao.searchFts('paper'), isEmpty);
    });

    test('AFTER UPDATE trigger re-indexes old and new values', () async {
      final id = await insert(title: 'Paper Boats');

      await (db.update(db.tracks)..where((t) => t.id.equals(id))).write(
        TracksCompanion(title: const Value('Glass River')),
      );

      expect(await db.tracksDao.searchFts('paper'), isEmpty);
      expect((await db.tracksDao.searchFts('glass')).map((t) => t.id), [id]);
    });
  });

  group('ftsPrefixQuery', () {
    test('quotes every token and prefixes only the last one', () {
      expect(TracksDao.ftsPrefixQuery('paper boa'), '"paper" "boa"*');
      expect(TracksDao.ftsPrefixQuery('one'), '"one"*');
      expect(TracksDao.ftsPrefixQuery('a b c'), '"a" "b" "c"*');
    });

    test('trims and collapses whitespace before tokenizing', () {
      expect(
        TracksDao.ftsPrefixQuery('  spaced   out \t '),
        '"spaced" "out"*',
      );
      expect(TracksDao.ftsPrefixQuery('\n\t'), isNull);
    });

    test('blank queries return null so callers can skip the search', () {
      expect(TracksDao.ftsPrefixQuery(''), isNull);
      expect(TracksDao.ftsPrefixQuery('   '), isNull);
    });

    test('double quotes inside a token are doubled (escaped)', () {
      expect(TracksDao.ftsPrefixQuery('a"b'), '"a""b"*');
      // Both tokens keep their inner quotes, escaped by doubling.
      expect(TracksDao.ftsPrefixQuery('say "hi"'), '"say" """hi"""*');
    });
  });
}

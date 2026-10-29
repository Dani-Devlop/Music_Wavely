/// Authored, awaiting local run.
///
/// No Flutter/Dart SDK exists in the authoring sandbox, so this suite has
/// never been executed. It targets the real `TracksDao` API in `lib/` and
/// needs `dart run build_runner build` first (generates `app_database.g.dart`
/// and the DAO mixins).
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavely/data/local/db/app_database.dart';

void main() {
  late AppDatabase db;
  var seq = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    seq = 0;
  });
  tearDown(() => db.close());

  /// Inserts one track row and returns its id. Every call gets a fresh
  /// `sourceTrackId` so the unique (sourceId, sourceTrackId) index never
  /// trips unless a test passes an explicit key.
  Future<int> insert({
    String title = 'Untitled',
    String artist = 'Aura',
    String? album,
    String? genre,
    String? language = 'en',
    int durationMs = 200000,
    int? bitrate,
    String format = 'mp3',
    bool explicit = false,
    String sourceId = 'local',
    String? sourceTrackId,
    int? playCount,
    DateTime? lastPlayedAt,
    DateTime? addedAt,
    DateTime? updatedAt,
  }) {
    final number = ++seq;
    return db.tracksDao.insertTrack(
      TracksCompanion.insert(
        sourceId: sourceId,
        sourceTrackId: sourceTrackId ?? 'hash-$number',
        title: title,
        artist: artist,
        album: Value(album),
        genre: Value(genre),
        language: Value(language),
        durationMs: durationMs,
        bitrate: Value(bitrate),
        format: format,
        explicit: Value(explicit),
        playCount: Value(playCount ?? 0),
        lastPlayedAt: Value(lastPlayedAt),
        addedAt: addedAt ?? DateTime(2024, 1, 1),
        updatedAt: updatedAt ?? DateTime(2024, 1, 1, 12),
      ),
    );
  }

  group('upsertBySource', () {
    test('insert path creates the row and returns the new entity', () async {
      final track = await db.tracksDao.upsertBySource(
        TracksCompanion.insert(
          sourceId: 'local',
          sourceTrackId: 'hash-1',
          title: 'First',
          artist: 'Aura',
          durationMs: 180000,
          format: 'mp3',
          addedAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 2),
        ),
      );

      expect(track.id, isNotNull);
      expect(track.title, 'First');
      expect(track.updatedAt, DateTime(2024, 1, 2));
      expect(await db.tracksDao.countAll(), 1);
    });

    test('update path preserves stats and addedAt, refreshes updatedAt',
        () async {
      final first = await db.tracksDao.upsertBySource(
        TracksCompanion.insert(
          sourceId: 'local',
          sourceTrackId: 'hash-1',
          title: 'First',
          artist: 'Aura',
          durationMs: 180000,
          format: 'mp3',
          addedAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 2),
        ),
      );
      // Give the row non-default playback stats to protect.
      await db.playsDao.incrementTrackPlayStats(first.id!);

      final second = await db.tracksDao.upsertBySource(
        // Plain companion: updatedAt left absent so the DAO stamps `now`.
        TracksCompanion(
          sourceId: const Value('local'),
          sourceTrackId: const Value('hash-1'),
          title: const Value('Renamed'),
          artist: const Value('Aura'),
          durationMs: const Value(190000),
          format: const Value('mp3'),
          bitrate: const Value(320),
          addedAt: Value(DateTime(2024, 1, 1)),
        ),
      );

      expect(second.id, first.id, reason: 'identity is the source key');
      expect(second.title, 'Renamed');
      expect(second.bitrate, 320);
      expect(second.addedAt, DateTime(2024, 1, 1), reason: 'preserved');
      expect(second.playCount, 1, reason: 'playCount is preserved');
      expect(second.lastPlayedAt, isNotNull, reason: 'preserved');
      expect(second.updatedAt.isAfter(DateTime(2024, 1, 2)), isTrue);
      expect(await db.tracksDao.countAll(), 1);
    });

    test('an explicit updatedAt on the entry is used verbatim', () async {
      final stamp = DateTime(2024, 5, 5, 5);
      final track = await db.tracksDao.upsertBySource(
        TracksCompanion.insert(
          sourceId: 'local',
          sourceTrackId: 'hash-1',
          title: 'First',
          artist: 'Aura',
          durationMs: 1,
          format: 'mp3',
          addedAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 2),
        ),
      );
      final updated = await db.tracksDao.upsertBySource(
        TracksCompanion(
          sourceId: const Value('local'),
          sourceTrackId: const Value('hash-1'),
          title: const Value('Second'),
          artist: const Value('Aura'),
          durationMs: const Value(1),
          format: const Value('mp3'),
          addedAt: Value(DateTime(2024, 1, 1)),
          updatedAt: Value(stamp),
        ),
      );

      expect(updated.id, track.id);
      expect(updated.updatedAt, stamp);
    });

    test('a different source key inserts a separate row', () async {
      TracksCompanion entry(String hash) => TracksCompanion.insert(
            sourceId: 'local',
            sourceTrackId: hash,
            title: 'T',
            artist: 'Aura',
            durationMs: 1,
            format: 'mp3',
            addedAt: DateTime(2024, 1, 1),
            updatedAt: DateTime(2024, 1, 1),
          );

      await db.tracksDao.upsertBySource(entry('hash-1'));
      await db.tracksDao.upsertBySource(entry('hash-2'));
      expect(await db.tracksDao.countAll(), 2);
    });
  });

  group('getAll', () {
    test('defaults to title ordering, case-folded', () async {
      await insert(title: 'banana');
      await insert(title: 'Apple');
      await insert(title: 'cherry');

      final titles =
          (await db.tracksDao.getAll(limit: 10, offset: 0))
              .map((t) => t.title)
              .toList();

      expect(titles, ['Apple', 'banana', 'cherry']);
    });

    test('limit + offset window over the ordered result', () async {
      await insert(title: 'banana');
      await insert(title: 'Apple');
      await insert(title: 'cherry');
      await insert(title: 'date');
      await insert(title: 'Elder');

      final page = await db.tracksDao.getAll(limit: 2, offset: 1);
      expect(page.map((t) => t.title), ['banana', 'cherry']);

      final beyond = await db.tracksDao.getAll(limit: 3, offset: 10);
      expect(beyond, isEmpty);
    });

    test('honors a custom ORDER BY fragment (trusted internal literal)',
        () async {
      for (var i = 1; i <= 5; i++) {
        await insert(title: 'T$i', playCount: i);
      }

      final byPlays = await db.tracksDao.getAll(
        limit: 3,
        offset: 0,
        orderBy: 'play_count DESC, id ASC',
      );
      expect(byPlays.map((t) => t.title), ['T5', 'T4', 'T3']);

      final newestFirst =
          await db.tracksDao.getAll(limit: 5, offset: 0, orderBy: 'id DESC');
      expect(newestFirst.map((t) => t.title).toList(), [
        'T5',
        'T4',
        'T3',
        'T2',
        'T1',
      ]);
    });
  });

  group('byArtist / byAlbum / byGenre', () {
    test('byArtist matches case-folded and sorts album then title', () async {
      await insert(title: 'zeta', artist: 'Aura', album: 'Beta');
      await insert(title: 'mid', artist: 'Aura', album: 'alpha');
      await insert(title: 'aaa', artist: 'AURA', album: 'Alpha');
      await insert(title: 'other', artist: 'Bo');

      final result = await db.tracksDao.byArtist('aura');

      expect(result.map((t) => t.title), ['aaa', 'mid', 'zeta']);
    });

    test('byAlbum matches artist+album case-folded, orders by title',
        () async {
      await insert(title: 'zeta', artist: 'Aura', album: 'Alpha');
      await insert(title: 'mid', artist: 'AURA', album: 'ALPHA');
      await insert(title: 'elsewhere', artist: 'Aura', album: 'Beta');

      final result = await db.tracksDao.byAlbum(
        artist: 'AURA',
        album: 'alpha',
      );

      expect(result.map((t) => t.title), ['mid', 'zeta']);
    });

    test('byGenre matches case-folded and orders by title', () async {
      await insert(title: 'zeta', genre: 'Rock');
      await insert(title: 'mid', genre: 'rock');
      await insert(title: 'aaa', genre: 'Pop');

      final result = await db.tracksDao.byGenre('ROCK');

      expect(result.map((t) => t.title), ['mid', 'zeta']);
    });

    test('tracks without album sort before album groups (empty album key)',
        () async {
      await insert(title: 'b-single', artist: 'Aura', album: null);
      await insert(title: 'a-lp', artist: 'Aura', album: 'Beta');

      final result = await db.tracksDao.byArtist('Aura');

      expect(result.map((t) => t.title), ['b-single', 'a-lp']);
    });
  });

  group('distinctArtists', () {
    test('groups case-folded with track and album counts, sorted', () async {
      await insert(title: 't1', artist: 'Aura', album: 'Alpha');
      await insert(title: 't2', artist: 'aura', album: 'Alpha');
      await insert(title: 't3', artist: 'Aura', album: 'Beta');
      await insert(title: 't4', artist: 'bo', album: null);

      final artists = await db.tracksDao.distinctArtists();

      expect(artists.map((a) => a.name), ['Aura', 'bo']);
      expect(artists[0].trackCount, 3);
      expect(artists[0].albumCount, 2);
      expect(artists[1].trackCount, 1);
      // COUNT(DISTINCT album) skips the NULL album.
      expect(artists[1].albumCount, 0);
      expect(artists.every((a) => a.coverPath == null), isTrue);
    });
  });

  group('distinctAlbums', () {
    test('groups by album x artist, newest first, null album folded',
        () async {
      // Helper default addedAt = 2024-01-01.
      await insert(title: 't1', artist: 'Aura', album: 'Sun');
      await insert(
        title: 't2',
        artist: 'Aura',
        album: 'Sun',
        addedAt: DateTime(2024, 1, 2),
      );
      await insert(
        title: 't3',
        artist: 'Aura',
        album: 'Moon',
        addedAt: DateTime(2024, 1, 3),
      );
      await insert(
        title: 't4',
        artist: 'Bo',
        album: null,
        addedAt: DateTime(2024, 1, 5),
      );

      final albums = await db.tracksDao.distinctAlbums();

      expect(albums.map((a) => a.title),
          ['Unknown Album', 'Moon', 'Sun']);
      expect(
        albums.map((a) => a.key),
        ['bo::unknown album', 'aura::moon', 'aura::sun'],
      );
      expect(albums[0].artist, 'Bo');
      expect(albums[1].trackCount, 1);
      expect(albums[2].trackCount, 2);
      expect(albums[2].addedAt, DateTime(2024, 1, 1),
          reason: 'first_added = MIN(added_at) of the group');
      expect(albums.every((a) => a.year == null), isTrue);
      expect(albums.every((a) => a.coverPath == null), isTrue);
    });
  });

  group('distinctGenres', () {
    test('distinct non-null genres, case-folded and sorted', () async {
      await insert(title: 't1', genre: 'Rock');
      await insert(title: 't2', genre: 'rock');
      await insert(title: 't3', genre: 'Pop');
      await insert(title: 't4', genre: null);

      final genres = await db.tracksDao.distinctGenres();

      expect(genres.map((g) => g.toLowerCase()), ['pop', 'rock']);
    });
  });

  group('counts', () {
    test('countBySource and countAll', () async {
      await insert(title: 't1');
      await insert(title: 't2');
      await insert(title: 'r1', sourceId: 'remote');

      expect(await db.tracksDao.countBySource('local'), 2);
      expect(await db.tracksDao.countBySource('remote'), 1);
      expect(await db.tracksDao.countBySource('missing'), 0);
      expect(await db.tracksDao.countAll(), 3);
    });
  });

  group('byIds', () {
    test('returns exactly the requested rows (db order, not input order)',
        () async {
      final id1 = await insert(title: 't1');
      final id2 = await insert(title: 't2');
      final id3 = await insert(title: 't3');

      final result = await db.tracksDao.byIds([id3, id1]);

      expect(result.map((t) => t.id).toSet(), {id1, id3});
      expect(result, hasLength(2));
      expect(result.every((t) => t.title != 't2'), isTrue);
    });

    test('empty input and unknown ids yield empty lists', () async {
      await insert(title: 't1');

      expect(await db.tracksDao.byIds(const []), isEmpty);
      expect(await db.tracksDao.byIds([9999]), isEmpty);
    });

    test('a single id keeps the byIds path simple', () async {
      final id = await insert(title: 't1');

      final result = await db.tracksDao.byIds([id]);

      expect(result.map((t) => t.title), ['t1']);
    });
  });

  group('upsertAlbumProjection', () {
    test('inserts once, then recomputes counts idempotently', () async {
      await insert(title: 't1', artist: 'Aura', album: 'Sun');
      await insert(title: 't2', artist: 'AURA', album: 'sun');

      await db.tracksDao.upsertAlbumProjection(
        title: 'Sun',
        artist: 'Aura',
      );

      var rows = await db.select(db.albums).get();
      expect(rows, hasLength(1));
      expect(rows.single.key, 'aura::sun');
      expect(rows.single.title, 'Sun');
      expect(rows.single.artist, 'Aura');
      expect(rows.single.trackCount, 2);
      final addedAtBefore = rows.single.addedAt;

      await insert(title: 't3', artist: 'Aura', album: 'Sun');
      await db.tracksDao.upsertAlbumProjection(
        title: 'Sun',
        artist: 'Aura',
        coverPath: '/covers/sun.png',
      );

      rows = await db.select(db.albums).get();
      expect(rows, hasLength(1), reason: 'idempotent on the unique key');
      expect(rows.single.trackCount, 3);
      expect(rows.single.coverPath, '/covers/sun.png');
      expect(rows.single.addedAt, addedAtBefore, reason: 'addedAt preserved');
    });

    test('a null coverPath leaves an existing cover untouched', () async {
      await insert(title: 't1', artist: 'Aura', album: 'Sun');
      await db.tracksDao.upsertAlbumProjection(
        title: 'Sun',
        artist: 'Aura',
        coverPath: '/covers/sun.png',
      );

      await db.tracksDao.upsertAlbumProjection(
        title: 'Sun',
        artist: 'Aura',
      );

      final row = await db.select(db.albums).getSingle();
      expect(row.coverPath, '/covers/sun.png');
    });
  });

  group('upsertArtistProjection', () {
    test('inserts once, aggregates case-folded, updates idempotently',
        () async {
      await insert(title: 't1', artist: 'Aura', album: 'Sun');
      await insert(title: 't2', artist: 'aura', album: 'Moon');

      await db.tracksDao.upsertArtistProjection(name: 'Aura');

      var rows = await db.select(db.artists).get();
      expect(rows, hasLength(1));
      expect(rows.single.name, 'Aura');
      expect(rows.single.trackCount, 2);
      expect(rows.single.albumCount, 2);

      await db.tracksDao.upsertArtistProjection(
        name: 'AURA',
        coverPath: '/artists/aura.png',
      );

      rows = await db.select(db.artists).get();
      expect(rows, hasLength(1), reason: 'name lookup is case-folded');
      expect(rows.single.coverPath, '/artists/aura.png');
      expect(rows.single.trackCount, 2);
      expect(rows.single.albumCount, 2);
    });

    test('recomputes counts after rows were removed', () async {
      final id1 = await insert(title: 't1', artist: 'Aura', album: 'Sun');
      final id2 = await insert(title: 't2', artist: 'Aura', album: 'Moon');
      await db.tracksDao.upsertArtistProjection(name: 'Aura');

      await (db.delete(db.tracks)
            ..where((t) => t.id.isIn([id1, id2])))
          .go();
      await db.tracksDao.upsertArtistProjection(name: 'Aura');

      final row = await db.select(db.artists).getSingle();
      expect(row.trackCount, 0);
      expect(row.albumCount, 0);
    });
  });
}

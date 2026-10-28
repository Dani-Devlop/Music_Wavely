/// Authored, awaiting local run.
///
/// No Flutter/Dart SDK exists in the authoring sandbox, so this suite has
/// never been executed. It targets the real `TrackMapper` and the generated
/// drift row/companion types; `dart run build_runner build` must run first
/// (generates `app_database.g.dart`).
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/mappers/track_mapper.dart';
import 'package:wavely/domain/entities/entities.dart';

void main() {
  group('toDomain (pure row mapping, no database)', () {
    test('maps every column 1:1', () {
      final row = TracksRow(
        id: 7,
        sourceId: 'local',
        sourceTrackId: 'path:size:mtime',
        title: 'Neon Rivers',
        artist: 'Vela',
        album: 'Tideline',
        genre: 'Synthwave',
        language: 'en',
        durationMs: 213000,
        bitrate: 320,
        format: 'flac',
        filePath: '/music/neon.flac',
        coverPath: '/covers/neon.png',
        explicit: true,
        addedAt: DateTime(2024, 2, 1),
        updatedAt: DateTime(2024, 2, 2),
        playCount: 4,
        lastPlayedAt: DateTime(2024, 2, 3),
      );

      final track = TrackMapper.toDomain(row);

      expect(track.id, 7);
      expect(track.sourceId, 'local');
      expect(track.sourceTrackId, 'path:size:mtime');
      expect(track.title, 'Neon Rivers');
      expect(track.artist, 'Vela');
      expect(track.album, 'Tideline');
      expect(track.genre, 'Synthwave');
      expect(track.language, 'en');
      expect(track.durationMs, 213000);
      expect(track.bitrate, 320);
      expect(track.format, 'flac');
      expect(track.filePath, '/music/neon.flac');
      expect(track.coverPath, '/covers/neon.png');
      expect(track.explicit, isTrue);
      expect(track.addedAt, DateTime(2024, 2, 1));
      expect(track.updatedAt, DateTime(2024, 2, 2));
      expect(track.playCount, 4);
      expect(track.lastPlayedAt, DateTime(2024, 2, 3));
    });

    test('maps null album / genre / language / bitrate / lastPlayedAt',
        () {
      final row = TracksRow(
        id: 1,
        sourceId: 'remote',
        sourceTrackId: 'remote-1',
        title: 'T',
        artist: 'A',
        album: null,
        genre: null,
        language: null,
        durationMs: 0,
        bitrate: null,
        format: 'mp3',
        filePath: null,
        coverPath: null,
        explicit: false,
        addedAt: DateTime(2024),
        updatedAt: DateTime(2024),
        playCount: 0,
        lastPlayedAt: null,
      );

      final track = TrackMapper.toDomain(row);

      expect(track.album, isNull);
      expect(track.genre, isNull);
      expect(track.language, isNull);
      expect(track.bitrate, isNull);
      expect(track.filePath, isNull);
      expect(track.coverPath, isNull);
      expect(track.lastPlayedAt, isNull);
    });

    test('toDomainList returns an unmodifiable list', () {
      final row = TracksRow(
        id: 1,
        sourceId: 'local',
        sourceTrackId: 'h',
        title: 'T',
        artist: 'A',
        album: null,
        genre: null,
        language: null,
        durationMs: 1,
        bitrate: null,
        format: 'mp3',
        filePath: null,
        coverPath: null,
        explicit: false,
        addedAt: DateTime(2024),
        updatedAt: DateTime(2024),
        playCount: 0,
        lastPlayedAt: null,
      );

      final tracks = TrackMapper.toDomainList([row, row]);

      expect(tracks, hasLength(2));
      expect(() => tracks.add(tracks.first), throwsUnsupportedError);
    });
  });

  group('toCompanion + database roundtrip', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });
    tearDown(() => db.close());

    test('companion persists every field; toDomain restores them', () async {
      final track = Track(
        sourceId: 'local',
        sourceTrackId: 'hash-roundtrip',
        title: 'Glass Harbour',
        artist: 'Vela',
        genre: 'Dream Pop',
        language: 'en',
        durationMs: 195000,
        format: 'mp3',
        explicit: true,
        addedAt: DateTime(2024, 2, 2, 8),
        updatedAt: DateTime(2024, 2, 3, 9),
        playCount: 4,
        lastPlayedAt: DateTime(2024, 2, 3, 9, 30),
      );

      final id = await db.tracksDao.insertTrack(
        TrackMapper.toCompanion(track),
      );
      final loaded = await db.tracksDao.getById(id);

      expect(loaded, isNotNull);
      expect(loaded!.id, id);
      expect(loaded.sourceId, track.sourceId);
      expect(loaded.sourceTrackId, track.sourceTrackId);
      expect(loaded.title, track.title);
      expect(loaded.artist, track.artist);
      expect(loaded.album, isNull, reason: 'entity album was null');
      expect(loaded.genre, track.genre);
      expect(loaded.language, track.language);
      expect(loaded.durationMs, track.durationMs);
      expect(loaded.bitrate, isNull);
      expect(loaded.format, track.format);
      expect(loaded.filePath, isNull);
      expect(loaded.coverPath, isNull);
      expect(loaded.explicit, isTrue);
      expect(loaded.addedAt, track.addedAt);
      expect(loaded.updatedAt, track.updatedAt);
      expect(loaded.playCount, 4);
      expect(loaded.lastPlayedAt, track.lastPlayedAt);
    });

    test('null entity fields clear existing columns (explicit Value(null))',
        () async {
      final id = await db.tracksDao.insertTrack(
        TracksCompanion.insert(
          sourceId: 'local',
          sourceTrackId: 'hash-clear',
          title: 'Rich Metadata',
          artist: 'Vela',
          album: const Value('Old Album'),
          genre: const Value('Rock'),
          language: const Value('en'),
          bitrate: const Value(320),
          durationMs: 1000,
          format: 'mp3',
          addedAt: DateTime(2024),
          updatedAt: DateTime(2024),
        ),
      );

      // DateTime has no const constructor, so no `const` here.
      final stripped = Track(
        sourceId: 'local',
        sourceTrackId: 'hash-clear',
        title: 'Stripped Metadata',
        artist: 'Vela',
        album: null,
        genre: null,
        language: null,
        durationMs: 1000,
        format: 'mp3',
        addedAt: DateTime(2024),
        updatedAt: DateTime(2024, 1, 2),
      );
      await (db.update(db.tracks)..where((t) => t.id.equals(id))).write(
        TrackMapper.toCompanion(stripped),
      );

      final row = await db.select(db.tracks).getSingle();
      expect(row.title, 'Stripped Metadata');
      expect(row.album, isNull, reason: 'null must clear, not be skipped');
      expect(row.genre, isNull);
      expect(row.language, isNull);
      expect(row.bitrate, isNull);
      expect(row.updatedAt, DateTime(2024, 1, 2));
    });
  });
}

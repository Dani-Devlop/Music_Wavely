/// Authored, awaiting local run.
///
/// No Flutter/Dart SDK exists in the authoring sandbox, so this suite has
/// never been executed. It targets the real drift APIs in `lib/` and needs
/// `dart run build_runner build` first (generates `app_database.g.dart`).
///
/// Exercises the real executor seam of [AppDatabase] — the constructor
/// accepts an optional [QueryExecutor], so tests run against a fully
/// in-memory SQLite (with FTS5, as shipped by the bundled sqlite3) instead
/// of the drift-flutter default open.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/migrations/0001_init.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test('schemaVersion is 2 (Stage 1.2 schema)', () {
    expect(db.schemaVersion, 2);
  });

  test('onCreate creates every base + Stage 1.2 table plus tracks_fts',
      () async {
    // Forces the lazy open, which runs onCreate (createAll + createFts).
    await db.customSelect('SELECT 1').getSingle();

    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .map((row) => row.read<String>('name'))
        .get();

    expect(
      tables,
      containsAll(<String>[
        // Stage 1.1 base tables.
        'tracks',
        'albums',
        'artists',
        'playlists',
        'playlist_items',
        'liked_tracks',
        'plays',
        'lyrics_cache',
        // Stage 1.2 tables (migration 0002).
        'http_cache',
        'sync_outbox',
        'blocked_words',
        'profiles_local',
        'parental_audit',
        'artist_follows',
        // FTS5 virtual table (migration 0001).
        'tracks_fts',
      ]),
    );
  });

  test('onCreate creates the three FTS5 sync triggers', () async {
    await db.customSelect('SELECT 1').getSingle();

    final triggers = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'trigger'")
        .map((row) => row.read<String>('name'))
        .get();

    expect(
      triggers,
      containsAll(<String>[
        Migration0001.triggerInsertName,
        Migration0001.triggerDeleteName,
        Migration0001.triggerUpdateName,
      ]),
    );
  });

  test('insert/select roundtrip on tracks via TracksDao', () async {
    // Whole-second DateTimes: drift stores them losslessly in its default
    // integer mode, so plain equality below also verifies the roundtrip.
    final addedAt = DateTime(2024, 3, 1, 12);
    final updatedAt = DateTime(2024, 3, 1, 12, 30);

    final id = await db.tracksDao.insertTrack(
      TracksCompanion.insert(
        sourceId: 'local',
        sourceTrackId: 'path:size:mtime-hash',
        title: 'Neon Rivers',
        artist: 'Vela',
        album: const Value('Tideline'),
        genre: const Value('Synthwave'),
        durationMs: 213000,
        bitrate: const Value(320),
        format: 'flac',
        filePath: const Value('/music/neon_rivers.flac'),
        addedAt: addedAt,
        updatedAt: updatedAt,
      ),
    );

    final track = await db.tracksDao.getById(id);
    expect(track, isNotNull);
    expect(track!.id, id);
    expect(track.sourceId, 'local');
    expect(track.sourceTrackId, 'path:size:mtime-hash');
    expect(track.title, 'Neon Rivers');
    expect(track.artist, 'Vela');
    expect(track.album, 'Tideline');
    expect(track.genre, 'Synthwave');
    expect(track.language, isNull);
    expect(track.durationMs, 213000);
    expect(track.bitrate, 320);
    expect(track.format, 'flac');
    expect(track.filePath, '/music/neon_rivers.flac');
    expect(track.coverPath, isNull);
    expect(track.explicit, isFalse, reason: 'column default is false');
    expect(track.playCount, 0, reason: 'column default is 0');
    expect(track.lastPlayedAt, isNull);
    // `updatedAt` has no SQL default — it persists exactly as supplied.
    expect(track.addedAt, addedAt);
    expect(track.updatedAt, updatedAt);
  });

  test('companion defaults apply for omitted optional columns', () async {
    final id = await db.tracksDao.insertTrack(
      TracksCompanion.insert(
        sourceId: 'local',
        sourceTrackId: 'hash-1',
        title: 'Minimal',
        artist: 'Aura',
        durationMs: 1,
        format: 'mp3',
        addedAt: DateTime(2024),
        updatedAt: DateTime(2024),
      ),
    );

    final track = await db.tracksDao.getById(id);
    expect(track!.album, isNull);
    expect(track.genre, isNull);
    expect(track.language, isNull);
    expect(track.bitrate, isNull);
    expect(track.filePath, isNull);
    expect(track.coverPath, isNull);
    expect(track.explicit, isFalse);
    expect(track.playCount, 0);
  });

  test('unique index on (sourceId, sourceTrackId) rejects duplicates',
      () async {
    Future<int> insert() => db.tracksDao.insertTrack(
          TracksCompanion.insert(
            sourceId: 'local',
            sourceTrackId: 'same-hash',
            title: 'T',
            artist: 'A',
            durationMs: 1,
            format: 'mp3',
            addedAt: DateTime(2024),
            updatedAt: DateTime(2024),
          ),
        );

    await insert();
    await expectLater(insert(), throwsA(anything));
    expect(await db.tracksDao.countAll(), 1);
  });
}

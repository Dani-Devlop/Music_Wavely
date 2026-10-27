/// Authored, awaiting local run.
///
/// No Flutter/Dart SDK exists in the authoring sandbox, so this suite has
/// never been executed. It targets the real migration wiring in
/// `app_database.dart` (MigrationStrategy + `Migration0001`/`Migration0002`)
/// and needs `dart run build_runner build` first (generates
/// `app_database.g.dart`).
///
/// The codebase uses drift's standard MigrationStrategy: `onCreate` runs
/// `m.createAll()` + the FTS5 bootstrap, `onUpgrade` recreates the FTS index
/// and runs the plain-Dart step list in `Migration0002`. Both paths are
/// tested against the real schema; the v1→v2 upgrade runs on a temp-file
/// database so the same connection can be reopened at a lower version.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/migrations/0001_init.dart';
import 'package:wavely/data/local/db/migrations/0002_stage_1_2.dart';

/// Stands in for a "version 1" database: drift's own generated DDL is used
/// for perfect fidelity, then the Stage 1.2 tables are dropped again so only
/// the v1 schema (base tables + FTS) remains. drift stamps user_version = 1
/// when this database opens.
class _V1SchemaAppDatabase extends AppDatabase {
  _V1SchemaAppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          for (final table in Migration0002.tableNames) {
            await customStatement('DROP TABLE IF EXISTS $table');
          }
          await createFts();
        },
      );
}

Future<List<String>> _schemaObjects(AppDatabase db, String type) {
  return db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = '$type'",
      )
      .map((row) => row.read<String>('name'))
      .get();
}

void main() {
  group('Migration0002 contract', () {
    test('tableNames lists the six Stage 1.2 tables', () {
      expect(Migration0002.tableNames, [
        'http_cache',
        'sync_outbox',
        'blocked_words',
        'profiles_local',
        'parental_audit',
        'artist_follows',
      ]);
    });
  });

  group('fresh install (onCreate)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });
    tearDown(() => db.close());

    test('creates all base + Stage 1.2 tables and the FTS5 table', () async {
      await db.customSelect('SELECT 1').getSingle();

      final tables = await _schemaObjects(db, 'table');
      expect(
        tables,
        containsAll(<String>[
          ...Migration0002.tableNames,
          'tracks',
          'albums',
          'artists',
          'plays',
          'lyrics_cache',
          'tracks_fts',
        ]),
      );
    });

    test('creates the FTS5 sync triggers', () async {
      await db.customSelect('SELECT 1').getSingle();

      final triggers = await _schemaObjects(db, 'trigger');
      expect(
        triggers,
        containsAll(<String>[
          Migration0001.triggerInsertName,
          Migration0001.triggerDeleteName,
          Migration0001.triggerUpdateName,
        ]),
      );
    });

    test('Stage 1.2 tables are usable through their DAOs right away',
        () async {
      await db.customSelect('SELECT 1').getSingle();

      await db.syncOutboxDao.enqueue(
        tableName: 'plays',
        rowKey: '1',
        op: 'insert',
        payload: '{}',
      );
      expect(await db.syncOutboxDao.count(), 1);

      await db.parentalDao.addWord(word: 'nope');
      expect(await db.parentalDao.allWords(), hasLength(1));

      await db.artistFollowsDao.follow('Aura');
      expect(await db.artistFollowsDao.isFollowing('Aura'), isTrue);

      await db.httpCacheDao.put(
        requestKey: 'key',
        body: 'body',
        statusCode: 200,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(await db.httpCacheDao.get('key'), 'body');
    });
  });

  group('upgrade v1 → v2 (onUpgrade)', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wavely_mig_test');
      dbFile = File('${tempDir.path}/db.sqlite');
    });
    tearDown(() => tempDir.delete(recursive: true));

    test('creates the Stage 1.2 tables and keeps v1 data', () async {
      // ---- build a genuine v1 database -----------------------------
      final v1 = _V1SchemaAppDatabase(NativeDatabase.file(dbFile));
      await v1.customSelect('SELECT 1').getSingle();

      final v1Tables = await _schemaObjects(v1, 'table');
      for (final table in Migration0002.tableNames) {
        expect(
          v1Tables,
          isNot(contains(table)),
          reason: '$table must not exist before the upgrade',
        );
      }
      expect(v1Tables, contains('tracks_fts'));

      final v1TrackId = await v1.tracksDao.insertTrack(
        TracksCompanion.insert(
          sourceId: 'local',
          sourceTrackId: 'hash-survivor',
          title: 'Migration Survivor',
          artist: 'Vela',
          durationMs: 1,
          format: 'mp3',
          addedAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        ),
      );
      await v1.close();

      // ---- reopen with the real database → onUpgrade(1, 2) ----------
      final db = AppDatabase(NativeDatabase.file(dbFile));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').getSingle();

      expect(db.schemaVersion, 2);

      final v2Tables = await _schemaObjects(db, 'table');
      for (final table in Migration0002.tableNames) {
        expect(v2Tables, contains(table),
            reason: '$table must exist after the upgrade');
      }

      final survivor = await db.tracksDao.getById(v1TrackId);
      expect(survivor, isNotNull);
      expect(survivor!.title, 'Migration Survivor');

      // The Stage 1.2 tables are immediately usable.
      await db.syncOutboxDao.enqueue(
        tableName: 'plays',
        rowKey: '1',
        op: 'insert',
        payload: '{}',
      );
      expect(await db.syncOutboxDao.count(), 1);
    });

    test('recreates a working FTS index (new rows become searchable)',
        () async {
      final v1 = _V1SchemaAppDatabase(NativeDatabase.file(dbFile));
      await v1.customSelect('SELECT 1').getSingle();
      await v1.tracksDao.insertTrack(
        TracksCompanion.insert(
          sourceId: 'local',
          sourceTrackId: 'hash-old',
          title: 'Old Song',
          artist: 'Vela',
          durationMs: 1,
          format: 'mp3',
          addedAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        ),
      );
      await v1.close();

      final db = AppDatabase(NativeDatabase.file(dbFile));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').getSingle();

      // onUpgrade dropped and recreated tracks_fts + its triggers, so rows
      // inserted AFTER the upgrade land in the fresh index again.
      final newTrackId = await db.tracksDao.insertTrack(
        TracksCompanion.insert(
          sourceId: 'local',
          sourceTrackId: 'hash-new',
          title: 'Upgrade Probe',
          artist: 'Vela',
          durationMs: 1,
          format: 'mp3',
          addedAt: DateTime(2024, 1, 2),
          updatedAt: DateTime(2024, 1, 2),
        ),
      );

      final hits = await db.tracksDao.searchFts('probe');
      expect(hits.map((t) => t.id), [newTrackId]);
    });

    test('creates the idx_sync_outbox_created index', () async {
      final v1 = _V1SchemaAppDatabase(NativeDatabase.file(dbFile));
      await v1.customSelect('SELECT 1').getSingle();
      await v1.close();

      final db = AppDatabase(NativeDatabase.file(dbFile));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').getSingle();

      final indexes = await _schemaObjects(db, 'index');
      expect(indexes, contains('idx_sync_outbox_created'));
    });
  });
}

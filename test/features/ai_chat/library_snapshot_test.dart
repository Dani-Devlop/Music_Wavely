/// Authored, awaiting local run (Task 2-f).
///
/// [LibrarySnapshot] privacy + cap contract against a real in-memory drift
/// database: 500-track cap (fed 600 fake tracks), counts over the FULL
/// library, play-count-desc/title-asc ordering, per-track compact keys
/// only ({t,a,al,g,l,id,d}) — never file paths or user-identifying fields.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/features/ai_chat/data/library_snapshot.dart';

Future<AppDatabase> _seed({
  required int count,
  String Function(int index)? titleFor,
  int Function(int index)? playCountFor,
  String Function(int index)? artistFor,
  String? Function(int index)? genreFor,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  for (var i = 0; i < count; i++) {
    await db.tracksDao.insertTrack(
      TracksCompanion.insert(
        sourceId: 'local',
        sourceTrackId: 'fake-$i',
        title: titleFor?.call(i) ?? 'Track ${i.toString().padLeft(4, '0')}',
        artist: artistFor?.call(i) ?? 'Artist ${i % 10}',
        album: Value(i.isEven ? 'Album ${i ~/ 20}' : null),
        genre: Value(genreFor?.call(i)),
        language: Value(i % 3 == 0 ? 'en' : null),
        durationMs: 100000 + i * 137,
        format: 'mp3',
        filePath: Value('/data/media/secret/file$i.mp3'),
        addedAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
        playCount: Value(playCountFor?.call(i) ?? 0),
      ),
    );
  }
  return db;
}

void main() {
  test('caps the snapshot at 500 tracks when fed 600', () async {
    final db = await _seed(count: 600);
    addTearDown(db.close);
    final snapshot = await LibrarySnapshot.build(tracksDao: db.tracksDao);
    final decoded = jsonDecode(snapshot) as Map<String, Object?>;
    final tracks = decoded['tracks'] as List<Object?>;
    expect(tracks, hasLength(LibrarySnapshot.maxTracks));
    expect(LibrarySnapshot.maxTracks, 500);
    // Counts are computed over the FULL library, not the cap.
    final counts = decoded['counts'] as Map<String, Object?>;
    expect(counts['totalTracks'], 600);
  });

  test('counts cover the full library: artists and sorted genres', () async {
    final db = await _seed(
      count: 8,
      artistFor: (i) => switch (i % 3) {
        0 => 'Aurora Sky',
        1 => 'Cedar Waves',
        _ => 'Blank Artist   ',
      },
      genreFor: (i) => switch (i % 4) {
        0 => 'Rock',
        1 => 'Pop',
        2 => 'Jazz',
        // Blank (whitespace-only) genres are skipped just like null.
        _ => '   ',
      },
    );
    addTearDown(db.close);
    final snapshot = await LibrarySnapshot.build(tracksDao: db.tracksDao);
    final decoded = jsonDecode(snapshot) as Map<String, Object?>;
    final counts = decoded['counts'] as Map<String, Object?>;
    // 'Blank Artist   ' trims to the same artistOrUnknown? No: the blank
    // check is isBlank on the RAW string — 'Blank Artist   ' is not blank,
    // so it counts as its own (untrimmed) artist value.
    expect(counts['artists'], 3);
    expect(counts['genres'], <String>['Jazz', 'Pop', 'Rock']);
  });

  test('orders tracks by play count desc, then title asc', () async {
    final db = await _seed(
      count: 5,
      titleFor: (i) => <String>['Alpha', 'Zulu', 'Bravo', 'Yankee', 'Echo'][i],
      playCountFor: (i) => <int>[1, 5, 5, 0, 3][i],
    );
    addTearDown(db.close);
    final snapshot = await LibrarySnapshot.build(tracksDao: db.tracksDao);
    final decoded = jsonDecode(snapshot) as Map<String, Object?>;
    final titles = <String>[
      for (final track in decoded['tracks'] as List<Object?>)
        (track as Map<String, Object?>)['t']! as String,
    ];
    expect(titles, <String>['Bravo', 'Zulu', 'Echo', 'Alpha', 'Yankee']);
  });

  test('track entries carry ONLY compact keys — no paths, no PII',
      () async {
    final db = await _seed(count: 3);
    addTearDown(db.close);
    final snapshot = await LibrarySnapshot.build(tracksDao: db.tracksDao);
    final decoded = jsonDecode(snapshot) as Map<String, Object?>;
    // Top-level shape is exactly tracks + counts.
    expect(decoded.keys.toSet(), <String>{'tracks', 'counts'});
    expect(
      (decoded['counts'] as Map<String, Object?>).keys.toSet(),
      <String>{'totalTracks', 'artists', 'genres'},
    );
    for (final entry in decoded['tracks'] as List<Object?>) {
      final track = entry as Map<String, Object?>;
      expect(track.keys.toSet(), <String>{'t', 'a', 'al', 'g', 'l', 'id', 'd'});
      expect(track['d'], isA<int>());
    }
    // Seeded absolute file paths and formats never leak into the payload.
    expect(snapshot.contains('/data/media/secret'), isFalse);
    expect(snapshot.contains('.mp3'), isFalse);
    expect(snapshot.contains('filePath'), isFalse);
    expect(snapshot.contains('coverPath'), isFalse);
    expect(snapshot.contains('sourceTrackId'), isFalse);
    expect(snapshot.contains('addedAt'), isFalse);
    // `d` is duration in whole seconds.
    final first = (decoded['tracks'] as List<Object?>).first
        as Map<String, Object?>;
    expect(first['d'], (100000 + ((first['id']! as int) - 1) * 137) ~/ 1000);
  });

  test('output is canonical compact JSON (no whitespace padding)', () async {
    final db = await _seed(count: 4);
    addTearDown(db.close);
    final snapshot = await LibrarySnapshot.build(tracksDao: db.tracksDao);
    // Re-encoding the decoded payload reproduces the string byte-for-byte,
    // proving jsonEncode's compact (space-free) form was used.
    expect(snapshot, jsonEncode(jsonDecode(snapshot)));
  });

  test('custom maxTracks override is respected', () async {
    final db = await _seed(count: 12);
    addTearDown(db.close);
    final snapshot = await LibrarySnapshot.build(
      tracksDao: db.tracksDao,
      maxTracks: 5,
    );
    final decoded = jsonDecode(snapshot) as Map<String, Object?>;
    expect(decoded['tracks'], hasLength(5));
    expect(
      (decoded['counts'] as Map<String, Object?>)['totalTracks'],
      12,
    );
  });

  test('empty library yields empty tracks with zero counts', () async {
    final db = await _seed(count: 0);
    addTearDown(db.close);
    final snapshot = await LibrarySnapshot.build(tracksDao: db.tracksDao);
    final decoded = jsonDecode(snapshot) as Map<String, Object?>;
    expect(decoded['tracks'], isEmpty);
    expect(
      decoded['counts'],
      <String, Object?>{
        'totalTracks': 0,
        'artists': 0,
        'genres': <String>[],
      },
    );
  });
}

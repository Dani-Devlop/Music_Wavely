/// Authored, awaiting local run.
///
/// No Flutter/Dart SDK exists in the authoring sandbox, so this suite has
/// never been executed. It targets the real `LyricsDao` API in `lib/` and
/// needs `dart run build_runner build` first (generates `app_database.g.dart`
/// and the DAO mixins).
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

  Future<int> insertTrack(String title) {
    return db.tracksDao.insertTrack(
      TracksCompanion.insert(
        sourceId: 'local',
        sourceTrackId: 'hash-$title',
        title: title,
        artist: 'Aura',
        durationMs: 1000,
        format: 'mp3',
        addedAt: DateTime(2024),
        updatedAt: DateTime(2024),
      ),
    );
  }

  Future<LyricsCacheRow> rowFor(int trackId, String provider) {
    return (db.select(db.lyricsCache)
          ..where(
            (r) => r.trackId.equals(trackId) & r.provider.equals(provider),
          ))
        .getSingle();
  }

  test('get returns null for a track without cached lyrics', () async {
    final trackId = await insertTrack('T1');

    expect(await db.lyricsDao.get(trackId: trackId), isNull);
    expect(
      await db.lyricsDao.get(trackId: trackId, provider: 'lrclib'),
      isNull,
    );
  });

  test('upsert writes a row that get returns by provider', () async {
    final trackId = await insertTrack('T1');

    await db.lyricsDao.upsert(
      trackId: trackId,
      provider: 'lrclib',
      syncedLrc: '[00:01.00] first line',
      plainText: 'first line',
    );

    final row = await db.lyricsDao.get(
      trackId: trackId,
      provider: 'lrclib',
    );
    expect(row, isNotNull);
    expect(row!.trackId, trackId);
    expect(row.provider, 'lrclib');
    expect(row.syncedLrc, '[00:01.00] first line');
    expect(row.plainText, 'first line');
    expect(row.offsetMs, 0, reason: 'default offset');
    expect(row.fetchedAt, isNotNull);
  });

  test('get without a provider prefers synced lyrics over plain text',
      () async {
    final trackId = await insertTrack('T1');
    await db.lyricsDao.upsert(
      trackId: trackId,
      provider: 'embedded',
      plainText: 'plain only',
    );
    await db.lyricsDao.upsert(
      trackId: trackId,
      provider: 'lrclib',
      syncedLrc: '[00:01.00] synced',
    );

    final best = await db.lyricsDao.get(trackId: trackId);

    expect(best!.provider, 'lrclib');
    expect(best.syncedLrc, '[00:01.00] synced');
  });

  test('among synced rows the most recently fetched one wins', () async {
    final trackId = await insertTrack('T1');
    // Direct inserts with explicit fetchedAt for deterministic ordering
    // (the DAO stamps `now`, which the second upsert below also proves).
    await db.into(db.lyricsCache).insert(
          LyricsCacheCompanion.insert(
            trackId: trackId,
            provider: 'older',
            syncedLrc: const Value('[00:01.00] old'),
            fetchedAt: DateTime(2024, 1, 1),
          ),
        );
    await db.into(db.lyricsCache).insert(
          LyricsCacheCompanion.insert(
            trackId: trackId,
            provider: 'newer',
            syncedLrc: const Value('[00:01.00] new'),
            fetchedAt: DateTime(2024, 1, 2),
          ),
        );

    final best = await db.lyricsDao.get(trackId: trackId);

    expect(best!.provider, 'newer');
  });

  test('upsert replaces on the same (track, provider) pair', () async {
    final trackId = await insertTrack('T1');
    await db.lyricsDao.upsert(
      trackId: trackId,
      provider: 'embedded',
      plainText: 'v1',
    );
    final first = await rowFor(trackId, 'embedded');

    await db.lyricsDao.upsert(
      trackId: trackId,
      provider: 'embedded',
      syncedLrc: '[00:01.00] v2',
    );
    final second = await rowFor(trackId, 'embedded');

    expect(await db.select(db.lyricsCache).get(), hasLength(1));
    expect(second.syncedLrc, '[00:01.00] v2');
    expect(second.plainText, 'v1', reason: 'COALESCE keeps old plain text');
    expect(second.offsetMs, 0, reason: 'new text resets the manual offset');
    expect(second.fetchedAt.isBefore(first.fetchedAt), isFalse);
  });

  test('updateOffset applies to every provider row of that track only',
      () async {
    final trackId = await insertTrack('T1');
    final otherTrackId = await insertTrack('T2');
    await db.lyricsDao.upsert(
      trackId: trackId,
      provider: 'embedded',
      plainText: 'a',
    );
    await db.lyricsDao.upsert(
      trackId: trackId,
      provider: 'lrclib',
      syncedLrc: '[00:01.00] b',
    );
    await db.lyricsDao.upsert(
      trackId: otherTrackId,
      provider: 'embedded',
      plainText: 'c',
    );

    await db.lyricsDao.updateOffset(trackId: trackId, offsetMs: 250);

    expect((await rowFor(trackId, 'embedded')).offsetMs, 250);
    expect((await rowFor(trackId, 'lrclib')).offsetMs, 250);
    expect((await rowFor(otherTrackId, 'embedded')).offsetMs, 0);
  });

  test('a fresh upsert resets the offset the user had applied', () async {
    final trackId = await insertTrack('T1');
    await db.lyricsDao.upsert(
      trackId: trackId,
      provider: 'lrclib',
      syncedLrc: '[00:01.00] a',
    );
    await db.lyricsDao.updateOffset(trackId: trackId, offsetMs: 250);

    await db.lyricsDao.upsert(
      trackId: trackId,
      provider: 'lrclib',
      syncedLrc: '[00:02.00] b',
    );

    final row = await rowFor(trackId, 'lrclib');
    expect(row.offsetMs, 0, reason: 'new lyrics invalidate the offset');
    expect(row.syncedLrc, '[00:02.00] b');
  });
}

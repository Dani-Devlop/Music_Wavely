// authored, awaiting local run.
//
// DriftLyricsCache tests (`lib/data/repositories/drift_lyrics_cache.dart`)
// over an in-memory Drift database. NOTE (read-both-files correction): the
// class implements the `LyricsCache` port from
// lib/features/lyrics/data/lyrics_cache.dart (a pure cache surface — get /
// upsert / updateOffset), NOT the domain `LyricsProvider` seam, and it has
// no upstream-provider chaining: the "miss -> delegate upstream" logic
// lives in LyricsRepository (lyrics feature), out of scope here. The miss
// path is therefore asserted as a null resolution, and the hit /
// write-through / best-row / offset semantics are asserted against the
// real LyricsDao SQL (COALESCE upsert, offset reset, synced-first rule).
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/repositories/drift_lyrics_cache.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/lyrics/data/lyrics_cache.dart';

void main() {
  late AppDatabase db;
  late DriftLyricsCache cache;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // lyrics_cache.trackId references the tracks table (FK) — seed rows.
    for (var i = 1; i <= 2; i++) {
      await db.tracksDao.insertTrack(
        TracksCompanion.insert(
          sourceId: Track.localSourceId,
          sourceTrackId: 'src-$i',
          title: 'Track $i',
          artist: 'Artist',
          durationMs: 60000,
          format: 'mp3',
          addedAt: DateTime(2024),
          updatedAt: DateTime(2024),
        ),
      );
    }
    cache = DriftLyricsCache(db.lyricsDao);
  });

  tearDown(() async {
    await db.close();
  });

  test('implements the LyricsCache port', () {
    final LyricsCache port = cache; // static conformance
    expect(port, same(cache));
  });

  group('cache miss path', () {
    test('an empty cache resolves to null', () async {
      expect(await cache.get(trackId: 1), isNull);
    });

    test('a miss for one track does not leak another track\'s row',
        () async {
      await cache.upsert(
        trackId: 1,
        provider: 'lrclib',
        syncedLrc: '[00:01.00]hello',
      );
      expect(await cache.get(trackId: 2), isNull);
    });

    test('a missing provider row resolves to null', () async {
      await cache.upsert(
        trackId: 1,
        provider: 'lrclib',
        syncedLrc: '[00:01.00]hello',
      );
      expect(
        await cache.get(trackId: 1, provider: 'embedded'),
        isNull,
      );
    });
  });

  group('cache hit path', () {
    test('upsert then get maps every CachedLyrics field', () async {
      await cache.upsert(
        trackId: 1,
        provider: 'lrclib',
        syncedLrc: '[00:01.00]First line\n[00:04.00]Second line',
      );

      final cached = await cache.get(trackId: 1);
      expect(cached, isNotNull);
      expect(cached!.trackId, 1);
      expect(cached.provider, 'lrclib');
      expect(cached.syncedLrc, contains('[00:01.00]'));
      expect(cached.plainText, isNull);
      expect(cached.offsetMs, 0);
      expect(cached.fetchedAt, isNotNull);
      expect(cached.hasSynced, isTrue);
    });

    test('provider filter returns exactly that provider row', () async {
      await cache.upsert(
        trackId: 1,
        provider: 'embedded',
        plainText: 'plain karaoke text',
      );
      await cache.upsert(
        trackId: 1,
        provider: 'lrclib',
        syncedLrc: '[00:01.00]synced line',
      );

      final embedded =
          await cache.get(trackId: 1, provider: 'embedded');
      expect(embedded!.provider, 'embedded');
      expect(embedded.plainText, 'plain karaoke text');
      expect(embedded.syncedLrc, isNull);

      final lrclib = await cache.get(trackId: 1, provider: 'lrclib');
      expect(lrclib!.provider, 'lrclib');
      expect(lrclib.syncedLrc, isNotNull);
    });

    test('no provider filter prefers the synced row (best-row rule)',
        () async {
      await cache.upsert(
        trackId: 1,
        provider: 'embedded',
        plainText: 'plain text',
      );
      await cache.upsert(
        trackId: 1,
        provider: 'lrclib',
        syncedLrc: '[00:01.00]synced line',
      );

      final best = await cache.get(trackId: 1);
      expect(best!.provider, 'lrclib');
      expect(best.hasSynced, isTrue);
    });
  });

  group('write-through semantics', () {
    test('upsert preserves fields omitted on update (COALESCE)', () async {
      await cache.upsert(
        trackId: 1,
        provider: 'lrclib',
        plainText: 'plain first',
      );
      await cache.upsert(
        trackId: 1,
        provider: 'lrclib',
        syncedLrc: '[00:01.00]synced now',
      );

      final row = await cache.get(trackId: 1, provider: 'lrclib');
      expect(row!.syncedLrc, '[00:01.00]synced now');
      expect(row.plainText, 'plain first'); // preserved
    });

    test('a full replace overwrites the supplied fields', () async {
      await cache.upsert(
        trackId: 1,
        provider: 'lrclib',
        syncedLrc: '[00:01.00]old',
      );
      await cache.upsert(
        trackId: 1,
        provider: 'lrclib',
        syncedLrc: '[00:02.00]new',
      );
      final row = await cache.get(trackId: 1, provider: 'lrclib');
      expect(row!.syncedLrc, '[00:02.00]new');
    });

    test('upsert resets a manual offset to 0', () async {
      await cache.upsert(
        trackId: 1,
        provider: 'lrclib',
        syncedLrc: '[00:01.00]line',
      );
      await cache.updateOffset(trackId: 1, offsetMs: 250);
      expect(
        (await cache.get(trackId: 1))!.offsetMs,
        250,
      );

      await cache.upsert(
        trackId: 1,
        provider: 'lrclib',
        syncedLrc: '[00:03.00]fresh lyrics',
      );
      expect(
        (await cache.get(trackId: 1))!.offsetMs,
        0,
        reason: 'new lyrics text invalidates the old manual offset',
      );
    });

    test('updateOffset applies to every provider row of the track',
        () async {
      await cache.upsert(
        trackId: 1,
        provider: 'embedded',
        plainText: 'plain',
      );
      await cache.upsert(
        trackId: 1,
        provider: 'lrclib',
        syncedLrc: '[00:01.00]line',
      );
      // A neighbour track must stay untouched by the offset update.
      await cache.upsert(
        trackId: 2,
        provider: 'lrclib',
        syncedLrc: '[00:01.00]other',
      );

      await cache.updateOffset(trackId: 1, offsetMs: -500);

      expect(
        (await cache.get(trackId: 1, provider: 'embedded'))!.offsetMs,
        -500,
      );
      expect(
        (await cache.get(trackId: 1, provider: 'lrclib'))!.offsetMs,
        -500,
      );
      expect((await cache.get(trackId: 2))!.offsetMs, 0);
    });
  });
}

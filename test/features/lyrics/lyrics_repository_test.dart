/// authored, awaiting local run.
///
/// Exercises the real `LyricsRepository` chain over hand-rolled fakes:
/// cache-first read, provider order (embedded -> remote, mirroring the
/// production wiring in `lyricsRepositoryProvider`), failure degradation,
/// winner caching and re-parse of cached rows. No network: the LRCLIB slot
/// is filled by a [ScriptedLyricsProvider] except in the final wiring test,
/// where an embedded cache hit short-circuits before any request.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/lyrics_provider.dart';
import 'package:wavely/features/lyrics/data/embedded_lyrics_provider.dart';
import 'package:wavely/features/lyrics/data/lyrics_cache.dart';
import 'package:wavely/features/lyrics/data/lyrics_repository.dart';

import 'fakes.dart';

LyricsResult _synced(List<(int, String)> stamps) => LyricsResult(
      synced: true,
      lines: <LyricLine>[
        for (final (int, String) s in stamps)
          LyricLine(
            startTime: Duration(milliseconds: s.$1),
            text: s.$2,
          ),
      ],
    );

LyricsResult _plain(String text) => LyricsResult(
      synced: false,
      lines: <LyricLine>[LyricLine(startTime: Duration.zero, text: text)],
    );

void main() {
  late FakeLyricsCache cache;
  late EmbeddedLyricsProvider embedded;
  late ScriptedLyricsProvider first;
  late ScriptedLyricsProvider second;
  late LyricsRepository repo;

  setUp(() {
    cache = FakeLyricsCache();
    embedded = EmbeddedLyricsProvider(cache: cache);
    first = ScriptedLyricsProvider('first');
    second = ScriptedLyricsProvider('second');
    repo = LyricsRepository(
      providers: <LyricsProvider>[embedded, first, second],
      cache: cache,
    );
  });

  group('short-circuits', () {
    test('track without an id resolves to null without touching anything',
        () async {
      final LyricsResult? result =
          await repo.fetch(makeTrack(title: 'No Id'));

      expect(result, isNull);
      expect(cache.getCallCount, 0);
      expect(first.calls, 0);
      expect(second.calls, 0);
    });

    test('cached synced row wins and providers are never consulted',
        () async {
      cache.seed(CachedLyrics(
        trackId: 7,
        provider: 'embedded',
        syncedLrc: '[00:01.00]cached\n[00:02.00]row\n',
        offsetMs: 0,
        fetchedAt: DateTime(2024, 1, 1),
      ));

      final LyricsResult? result = await repo.fetch(makeTrack(id: 7));

      expect(result!.synced, isTrue);
      expect(result.lines[1].text, 'row');
      expect(first.calls, 0);
      expect(second.calls, 0);
    });

    test('cached plain row parses as unsynced text', () async {
      cache.seed(CachedLyrics(
        trackId: 8,
        provider: 'lrclib',
        plainText: 'just words',
        offsetMs: 0,
        fetchedAt: DateTime(2024, 1, 1),
      ));

      final LyricsResult? result = await repo.fetch(makeTrack(id: 8));

      expect(result!.synced, isFalse);
      expect(result.lines.single.text, 'just words');
    });

    test('cache row with only blank plain text resolves to null', () async {
      cache.seed(CachedLyrics(
        trackId: 9,
        provider: 'lrclib',
        plainText: '   ',
        offsetMs: 0,
        fetchedAt: DateTime(2024, 1, 1),
      ));

      expect(await repo.fetch(makeTrack(id: 9)), isNull);
    });
  });

  group('provider chain', () {
    test('first non-null provider wins and later ones are not consulted',
        () async {
      first.result = _plain('from first');

      final LyricsResult? result = await repo.fetch(makeTrack(id: 1));

      expect(result!.lines.single.text, 'from first');
      expect(first.calls, 1);
      expect(second.calls, 0);
    });

    test('embedded provider reads the cache before scripted remotes',
        () async {
      cache.seed(CachedLyrics(
        trackId: 2,
        provider: EmbeddedLyricsProvider.providerId,
        plainText: 'embedded words',
        offsetMs: 0,
        fetchedAt: DateTime(2024, 1, 1),
      ));
      first.result = _plain('from first');

      final LyricsResult? result = await repo.fetch(makeTrack(id: 2));

      expect(result!.lines.single.text, 'embedded words');
      expect(first.calls, 0);
    });

    test('a throwing provider degrades to the next one', () async {
      first.error = Exception('network down');
      second.result = _plain('from second');

      final LyricsResult? result = await repo.fetch(makeTrack(id: 3));

      expect(result!.lines.single.text, 'from second');
      expect(first.calls, 1);
      expect(second.calls, 1);
    });

    test('a provider returning empty lines counts as a miss', () async {
      first.result = const LyricsResult(lines: <LyricLine>[]);
      second.result = _plain('from second');

      final LyricsResult? result = await repo.fetch(makeTrack(id: 4));

      expect(result!.lines.single.text, 'from second');
      expect(first.calls, 1);
      expect(second.calls, 1);
    });

    test('all providers missing resolves to null and caches nothing',
        () async {
      final LyricsResult? result = await repo.fetch(makeTrack(id: 5));

      expect(result, isNull);
      expect(cache.upserts, isEmpty);
      expect(cache.rowFor(5), isNull);
    });
  });

  group('caching of remote results', () {
    test('synced winner is re-serialized as LRC and refetch short-circuits',
        () async {
      first.result = _synced([(1000, 'one'), (2500, 'two')]);

      final LyricsResult? firstFetch = await repo.fetch(makeTrack(id: 6));

      expect(cache.upserts, hasLength(1));
      expect(cache.upserts.single.provider, 'first');
      expect(cache.upserts.single.syncedLrc, '[00:01.00]one\n[00:02.50]two');
      expect(cache.upserts.single.plainText, isNull);

      final LyricsResult? secondFetch = await repo.fetch(makeTrack(id: 6));
      expect(firstFetch!.lines[1].text, secondFetch!.lines[1].text);
      expect(secondFetch.lines[1].startTime, const Duration(
        milliseconds: 2500,
      ));
      expect(first.calls, 1, reason: 'second fetch must hit the cache');
      expect(second.calls, 0);
    });

    test('unsynced winner is cached as plain text', () async {
      first.result = _plain('plain payload');

      await repo.fetch(makeTrack(id: 11));

      expect(cache.upserts.single.syncedLrc, isNull);
      expect(cache.upserts.single.plainText, 'plain payload');
    });

    test('cache write failures do not break delivery and are not retried',
        () async {
      cache.upsertError = Exception('disk full');
      first.result = _plain('still delivered');

      final LyricsResult? result = await repo.fetch(makeTrack(id: 12));

      expect(result!.lines.single.text, 'still delivered');
      expect(cache.upserts, isEmpty);
    });
  });

  group('composition wiring', () {
    test('lyricsRepositoryProvider uses embedded-first over the cache port',
        () async {
      final FakeLyricsCache wired = FakeLyricsCache();
      wired.seed(CachedLyrics(
        trackId: 13,
        provider: 'embedded',
        syncedLrc: '[00:03.00]wired\n',
        offsetMs: 0,
        fetchedAt: DateTime(2024, 1, 1),
      ));
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          lyricsCacheProvider.overrideWithValue(wired),
        ],
      );
      addTearDown(container.dispose);

      final LyricsResult? result = await container
          .read(lyricsRepositoryProvider)
          .fetch(makeTrack(id: 13));

      expect(result!.lines.single.text, 'wired');
      expect(wired.getCallCount, greaterThanOrEqualTo(1));
      // No network happened: the embedded row short-circuits the chain.
      expect(wired.upserts, isEmpty);
    });
  });
}

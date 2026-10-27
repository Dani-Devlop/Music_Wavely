// authored, awaiting local run.
//
// Stage 1.2 (B7) advanced shuffle pipeline tests
// (`lib/playback/shuffle/advanced_shuffle.dart`).
//
// Eight fixed-seed scenario tests cover the documented pipeline
// (filter -> weighted seeded order -> anchor -> no-repeat window):
// (a) language allow filter, (b) blocked genre, (c) blocked artist,
// (d) explicit flag, (e) play-count weighting bias, (f) same-seed
// determinism, (g) no-repeat window, (h) empty pool after filters.
// Plus: the current-track anchor survives its own filter, the pool is
// never mutated, and a ShuffleConfig JSON roundtrip check.
//
// Implementation note pinned by these tests: `allowedArtistIds` /
// `blockedArtistIds` match the artist NAME (lower-cased), not an id —
// that is what `AdvancedShuffle._passes` actually compares against.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/shuffle/advanced_shuffle.dart';

Track _track(
  int id, {
  String? language,
  String? genre,
  String artist = 'Aria Wave',
  bool explicit = false,
  int playCount = 0,
}) =>
    Track(
      id: id,
      sourceId: Track.localSourceId,
      sourceTrackId: 'src-$id',
      title: 'Track $id',
      artist: artist,
      genre: genre,
      language: language,
      durationMs: 60000 + id,
      format: 'mp3',
      filePath: '/audio/$id.mp3',
      explicit: explicit,
      playCount: playCount,
      addedAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

void main() {
  const shuffle = AdvancedShuffle();

  group('(a) language filters', () {
    test('allowedLanguages keeps only the allowed language', () {
      final pool = <Track>[
        _track(1, language: 'eng'),
        _track(2, language: 'eng'),
        _track(3, language: 'jpn'),
        _track(4, language: 'kor'),
      ];
      final result = shuffle.shuffle(
        pool,
        currentIndex: null,
        config: const ShuffleConfig(
          allowedLanguages: {'eng'},
          seed: 1,
        ),
      );
      expect(result.map((t) => t.language).toSet(), <String>{'eng'});
      expect(result, hasLength(2));
    });

    test('blockedLanguages removes just the blocked language', () {
      final pool = <Track>[
        _track(1, language: 'eng'),
        _track(2, language: 'jpn'),
        _track(3, language: 'eng'),
      ];
      final result = shuffle.shuffle(
        pool,
        currentIndex: null,
        config: const ShuffleConfig(
          blockedLanguages: {'jpn'},
          seed: 1,
        ),
      );
      expect(result, hasLength(2));
      expect(result.every((t) => t.language != 'jpn'), isTrue);
    });

    test('filters are case-insensitive on language tags', () {
      final pool = <Track>[_track(1, language: 'ENG')];
      final result = shuffle.shuffle(
        pool,
        currentIndex: null,
        config: const ShuffleConfig(allowedLanguages: {'eng'}, seed: 1),
      );
      expect(result, hasLength(1));
    });

    test('tracks without a language pass an allow-list (documented rule)',
        () {
      final pool = <Track>[_track(1), _track(2, language: 'jpn')];
      final result = shuffle.shuffle(
        pool,
        currentIndex: null,
        config: const ShuffleConfig(allowedLanguages: {'eng'}, seed: 1),
      );
      expect(result.map((t) => t.id).toSet(), <int>{1});
    });
  });

  group('(b) blocked genres', () {
    test('a blocked genre never reaches the result', () {
      final pool = <Track>[
        _track(1, genre: 'metal'),
        _track(2, genre: 'rock'),
        _track(3, genre: 'Metal'),
        _track(4, genre: 'pop'),
      ];
      final result = shuffle.shuffle(
        pool,
        currentIndex: null,
        config: const ShuffleConfig(blockedGenres: {'metal'}, seed: 2),
      );
      expect(result.map((t) => t.id).toSet(), <int>{2, 4});
    });

    test('allowedGenres restricts the pool when non-empty', () {
      final pool = <Track>[
        _track(1, genre: 'rock'),
        _track(2, genre: 'pop'),
        _track(3, genre: 'jazz'),
      ];
      final result = shuffle.shuffle(
        pool,
        currentIndex: null,
        config: const ShuffleConfig(allowedGenres: {'pop'}, seed: 2),
      );
      expect(result.map((t) => t.id), <int>[2]);
    });
  });

  group('(c) blocked artists', () {
    test('blockedArtistIds excludes the artist name (case-folded)', () {
      final pool = <Track>[
        _track(1, artist: 'Aria Wave'),
        _track(2, artist: 'Kodo Line'),
        _track(3, artist: 'kodo line'),
        _track(4, artist: 'Mirren Vale'),
      ];
      final result = shuffle.shuffle(
        pool,
        currentIndex: null,
        config: const ShuffleConfig(
          blockedArtistIds: {'kodo line'},
          seed: 3,
        ),
      );
      expect(result.map((t) => t.artist).toSet(),
          <String>{'Aria Wave', 'Mirren Vale'});
    });

    test('allowedArtistIds keeps only the allowed artists', () {
      final pool = <Track>[
        _track(1, artist: 'Aria Wave'),
        _track(2, artist: 'Kodo Line'),
      ];
      final result = shuffle.shuffle(
        pool,
        currentIndex: null,
        config: const ShuffleConfig(
          allowedArtistIds: {'aria wave'},
          seed: 3,
        ),
      );
      expect(result.map((t) => t.id), <int>[1]);
    });
  });

  group('(d) explicit flag', () {
    final pool = <Track>[
      _track(1, explicit: true),
      _track(2),
      _track(3, explicit: true),
      _track(4),
      _track(5, explicit: true),
    ];

    test('includeExplicit=false drops every explicit track', () {
      final result = shuffle.shuffle(
        pool,
        currentIndex: null,
        config: const ShuffleConfig(includeExplicit: false, seed: 4),
      );
      expect(result.map((t) => t.id).toSet(), <int>{2, 4});
    });

    test('includeExplicit=true keeps the whole pool', () {
      final result = shuffle.shuffle(
        pool,
        currentIndex: null,
        config: const ShuffleConfig(includeExplicit: true, seed: 4),
      );
      expect(result, hasLength(pool.length));
    });
  });

  group('(e) play-count weighting bias (fixed seed)', () {
    test('weighting=1 biases hot tracks into the top half', () {
      // 100 hot tracks (playCount 100 -> weight 2.0) vs 100 cold tracks
      // (playCount 1 -> weight ~1.001). The Efraimidis-Spirakis key
      // pow(roll, 1/weight) gives a hot track ~2/3 pairwise win chance,
      // so ~2/3 of the top half is expected to be hot; the fixed seed
      // makes the exact outcome deterministic and the assertion is a
      // generous statistical bound, not an exact count.
      final pool = <Track>[
        for (var i = 1; i <= 100; i++) _track(i, playCount: 100),
        for (var i = 101; i <= 200; i++) _track(i, playCount: 1),
      ];
      final result = shuffle.shuffle(
        pool,
        currentIndex: null,
        config: const ShuffleConfig(weighting: 1, seed: 20240601),
      );
      expect(result, hasLength(200));
      final hotInTopHalf =
          result.take(100).where((t) => t.playCount == 100).length;
      expect(hotInTopHalf, greaterThanOrEqualTo(55),
          reason: 'weighted shuffle should bias hot tracks to the front');
      // Weighting is probabilistic, not a stable sort: some cold tracks
      // must still surface early.
      expect(hotInTopHalf, lessThan(100));
    });

    test('weighting=0 with the same seed is a uniform shuffle', () {
      final pool = <Track>[
        for (var i = 1; i <= 60; i++) _track(i, playCount: i),
      ];
      final result = shuffle.shuffle(
        pool,
        currentIndex: null,
        config: const ShuffleConfig(weighting: 0, seed: 5),
      );
      // Uniform: every track is present, order fixed by the seed.
      expect(result.map((t) => t.id).toSet(),
          <int>{for (var i = 1; i <= 60; i++) i});
    });
  });

  group('(f) same-seed determinism', () {
    test('two runs with the same seed produce the identical order', () {
      List<Track> buildPool() => <Track>[
            for (var i = 1; i <= 30; i++)
              _track(
                i,
                genre: i.isEven ? 'rock' : 'pop',
                artist: i % 3 == 0 ? 'Kodo Line' : 'Aria Wave',
                playCount: i,
              ),
          ];
      const config = ShuffleConfig(seed: 1234, weighting: 0.5);
      final first = shuffle.shuffle(buildPool(), currentIndex: null,
          config: config);
      final second = shuffle.shuffle(buildPool(), currentIndex: null,
          config: config);
      expect(first.map((t) => t.id), orderedEquals(second.map((t) => t.id)));
    });
  });

  group('(g) no-repeat window', () {
    test('recent ids never sit inside the window behind the anchor', () {
      final pool = <Track>[for (var i = 1; i <= 12; i++) _track(i)];
      final result = shuffle.shuffle(
        pool,
        currentIndex: 0, // anchor id 1 — itself recent, stays at position 0
        config: const ShuffleConfig(seed: 5, noRepeatWindow: 3),
        recentlyPlayedIds: const <int>[1, 2, 3, 4, 5],
      );
      expect(result.first.id, 1);
      for (var i = 1; i < 3; i++) {
        expect(
          const <int>{1, 2, 3, 4, 5}.contains(result[i].id),
          isFalse,
          reason: 'position $i holds recent id ${result[i].id}',
        );
      }
    });

    test('default window (10) pushes a large recent set beyond position 9',
        () {
      final pool = <Track>[for (var i = 1; i <= 20; i++) _track(i)];
      final recent = <int>[for (var i = 1; i <= 8; i++) i];
      final result = shuffle.shuffle(
        pool,
        currentIndex: null,
        config: const ShuffleConfig(seed: 6),
        recentlyPlayedIds: recent,
      );
      // Without an anchor, position 0 is exempt (the window pass starts at
      // index 1); every slot behind it must be fresh.
      for (var i = 1; i < 10; i++) {
        expect(recent.contains(result[i].id), isFalse,
            reason: 'position $i holds recent id ${result[i].id}');
      }
      expect(result, hasLength(20));
    });
  });

  group('(h) empty pool after filters', () {
    test('everything blocked -> graceful empty result', () {
      final pool = <Track>[
        _track(1, genre: 'metal'),
        _track(2, genre: 'metal'),
      ];
      final result = shuffle.shuffle(
        pool,
        currentIndex: null,
        config: const ShuffleConfig(blockedGenres: {'metal'}, seed: 8),
      );
      expect(result, isEmpty);
    });

    test('all blocked but the current track still anchors the result', () {
      final pool = <Track>[
        _track(1, genre: 'rock'),
        _track(2, genre: 'metal'),
        _track(3, genre: 'metal'),
      ];
      final result = shuffle.shuffle(
        pool,
        currentIndex: 1,
        config: const ShuffleConfig(blockedGenres: {'metal'}, seed: 8),
      );
      // The current track survives its own shuffle config (playback must
      // never be interrupted); the filtered remainder follows.
      expect(result.map((t) => t.id), <int>[2, 1]);
    });

    test('empty input pool -> empty result', () {
      final result = shuffle.shuffle(
        <Track>[],
        currentIndex: null,
        config: const ShuffleConfig(seed: 8),
      );
      expect(result, isEmpty);
    });
  });

  group('anchor + pool contract', () {
    test('the current track survives its own filter and leads the queue',
        () {
      final pool = <Track>[
        _track(1, genre: 'rock'),
        _track(2, genre: 'metal'),
        _track(3, genre: 'pop'),
        _track(4, genre: 'metal'),
        _track(5, genre: 'jazz'),
      ];
      final result = shuffle.shuffle(
        pool,
        currentIndex: 3,
        config: const ShuffleConfig(blockedGenres: {'metal'}, seed: 21),
      );
      expect(result.first, same(pool[3]));
      expect(
        result.skip(1).map((t) => t.genre).toSet(),
        <String>{'rock', 'pop', 'jazz'},
      );
      expect(result, hasLength(4)); // anchor + 3 filtered survivors
    });

    test('shuffle never mutates the input pool', () {
      final pool = <Track>[
        _track(1, genre: 'rock'),
        _track(2, genre: 'pop'),
        _track(3, genre: 'jazz'),
      ];
      final snapshot = pool.map((t) => t.id).toList();
      shuffle.shuffle(
        pool,
        currentIndex: 2,
        config: const ShuffleConfig(seed: 9),
        recentlyPlayedIds: const <int>[1],
      );
      expect(pool.map((t) => t.id), orderedEquals(snapshot));
    });

    test('single candidate + anchor keeps the anchor and the survivor', () {
      final pool = <Track>[
        _track(1, genre: 'pop'),
        _track(2, genre: 'metal'),
      ];
      final result = shuffle.shuffle(
        pool,
        currentIndex: 1,
        config: const ShuffleConfig(blockedGenres: {'metal'}, seed: 9),
      );
      expect(result.map((t) => t.id), <int>[2, 1]);
    });
  });

  group('ShuffleConfig (de)serialization', () {
    test('JSON roundtrip keeps every persisted knob', () {
      const config = ShuffleConfig(
        allowedLanguages: {'eng'},
        blockedLanguages: {'jpn'},
        allowedGenres: {'rock'},
        blockedGenres: {'metal'},
        allowedArtistIds: {'aria wave'},
        blockedArtistIds: {'kodo line'},
        includeExplicit: false,
        weighting: 0.5,
        noRepeatWindow: 4,
        seed: 99,
      );
      final restored = ShuffleConfig.fromJson(config.toJson());
      expect(restored.allowedLanguages, <String>{'eng'});
      expect(restored.blockedLanguages, <String>{'jpn'});
      expect(restored.allowedGenres, <String>{'rock'});
      expect(restored.blockedGenres, <String>{'metal'});
      expect(restored.allowedArtistIds, <String>{'aria wave'});
      expect(restored.blockedArtistIds, <String>{'kodo line'});
      expect(restored.includeExplicit, isFalse);
      expect(restored.weighting, 0.5);
      expect(restored.noRepeatWindow, 4);
      // The seed is runtime-only and is deliberately not persisted.
      expect(restored.seed, isNull);
    });

    test('weighting is clamped into [0, 1] on load', () {
      final restored = ShuffleConfig.fromJson(<String, Object?>{
        'weighting': 5,
      });
      expect(restored.weighting, 1);
    });

    test('defaults apply for missing json keys', () {
      final restored = ShuffleConfig.fromJson(<String, Object?>{});
      expect(restored.includeExplicit, isTrue);
      expect(restored.weighting, 0);
      expect(restored.noRepeatWindow, greaterThanOrEqualTo(1));
    });
  });

  // Keeps `dart:math` referenced for the pow() contract context and any
  // future seed experiments without tripping an unused-import lint.
  test('math helper sanity (pow monotonicity used by the weighting key)',
      () {
    expect(pow(0.25, 1 / 2), greaterThan(pow(0.25, 1)));
  });
}

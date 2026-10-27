// authored, awaiting local run.
//
// Unit tests for the Stage 1.1 deterministic Fisher-Yates shuffle
// (`lib/playback/shuffle/basic_shuffle.dart`): seeded determinism, full
// permutation (no loss / no duplicates), empty and single-element edge
// cases, current-track anchoring, and the recent-ids no-repeat window
// (`AppConstants.shuffleNoRepeatWindow` == 10).
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/shuffle/basic_shuffle.dart';

Track _track(int id) => Track(
      id: id,
      sourceId: Track.localSourceId,
      sourceTrackId: 'src-$id',
      title: 'Track $id',
      artist: 'Artist ${id % 5}',
      durationMs: 60000 + id,
      format: 'mp3',
      filePath: '/audio/$id.mp3',
      addedAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

List<Track> _pool(int count) => <Track>[
      for (var i = 1; i <= count; i++) _track(i),
    ];

Set<int> _ids(List<Track> tracks) => <int>{for (final t in tracks) t.id!};

void main() {
  const shuffle = BasicShuffle();

  group('determinism (fixed seed)', () {
    test('same seed + same input -> identical order', () {
      final pool = _pool(24);
      final first = shuffle.shuffle(pool, currentIndex: null, seed: 42);
      final second = shuffle.shuffle(pool, currentIndex: null, seed: 42);
      expect(first.map((t) => t.id), orderedEquals(second.map((t) => t.id)));
    });

    test('the seeded order differs from the input order', () {
      final pool = _pool(24);
      final shuffled = shuffle.shuffle(pool, currentIndex: null, seed: 42);
      expect(
        shuffled.map((t) => t.id),
        isNot(orderedEquals(pool.map((t) => t.id))),
      );
    });

    test('seed 0 and a large seed are both stable across runs', () {
      final pool = _pool(12);
      final a = shuffle.shuffle(pool, currentIndex: 3, seed: 0);
      final b = shuffle.shuffle(pool, currentIndex: 3, seed: 0);
      final c = shuffle.shuffle(pool, currentIndex: 3, seed: 2147483647);
      final d = shuffle.shuffle(pool, currentIndex: 3, seed: 2147483647);
      expect(a.map((t) => t.id), orderedEquals(b.map((t) => t.id)));
      expect(c.map((t) => t.id), orderedEquals(d.map((t) => t.id)));
    });
  });

  group('full permutation (no loss, no duplicates)', () {
    test('ids survive exactly once for 1..20 tracks', () {
      final pool = _pool(20);
      for (var seed = 0; seed < 5; seed++) {
        final shuffled = shuffle.shuffle(pool, currentIndex: null, seed: seed);
        expect(shuffled, hasLength(pool.length));
        // Sort both sides: the result must be a permutation of the input.
        final originalSorted = pool.map((t) => t.id).toList()..sort();
        final resultSorted = shuffled.map((t) => t.id).toList()..sort();
        expect(resultSorted, orderedEquals(originalSorted));
        expect(_ids(shuffled), hasLength(pool.length)); // no duplicates
      }
    });

    test('does not mutate the input list', () {
      final pool = _pool(10);
      final snapshot = pool.map((t) => t.id).toList();
      shuffle.shuffle(pool, currentIndex: 4, seed: 7);
      expect(pool.map((t) => t.id), orderedEquals(snapshot));
    });
  });

  group('edge cases', () {
    test('empty list -> empty list', () {
      final result = shuffle.shuffle(<Track>[], currentIndex: null, seed: 5);
      expect(result, isEmpty);
    });

    test('single element -> the same single element', () {
      final pool = _pool(1);
      final result = shuffle.shuffle(pool, currentIndex: 0, seed: 5);
      expect(result.map((t) => t.id), orderedEquals(pool.map((t) => t.id)));
    });

    test('two elements swap or keep, but stay a permutation', () {
      final pool = _pool(2);
      final result = shuffle.shuffle(pool, currentIndex: null, seed: 9);
      expect(result.map((t) => t.id).toSet(), _ids(pool));
    });

    test('out-of-range currentIndex is ignored (still a permutation)', () {
      final pool = _pool(6);
      final result = shuffle.shuffle(pool, currentIndex: 99, seed: 3);
      expect(result.map((t) => t.id).toSet(), _ids(pool));
    });
  });

  group('current-track anchor', () {
    test('the track at currentIndex becomes the first element', () {
      final pool = _pool(10);
      final result = shuffle.shuffle(pool, currentIndex: 6, seed: 123);
      expect(result.first.id, pool[6].id);
      expect(result.map((t) => t.id).toSet(), _ids(pool));
    });

    test('currentIndex null leaves the shuffle order untouched at front', () {
      final pool = _pool(10);
      final plain = shuffle.shuffle(pool, currentIndex: null, seed: 123);
      final again = shuffle.shuffle(pool, currentIndex: null, seed: 123);
      expect(plain.map((t) => t.id), orderedEquals(again.map((t) => t.id)));
    });
  });

  group('no-repeat window (recentlyPlayedIds)', () {
    // Window is AppConstants.shuffleNoRepeatWindow == 10; the pool has
    // exactly 10 fresh candidates so every recent id can be pushed out.
    test('unanchored: recent ids never sit inside the first window', () {
      final pool = _pool(20);
      final recent = <int>[for (var i = 1; i <= 10; i++) i];
      final result = shuffle.shuffle(
        pool,
        currentIndex: null,
        seed: 11,
        recentlyPlayedIds: recent,
      );
      for (var i = 0; i < AppConstants.shuffleNoRepeatWindow; i++) {
        expect(recent.contains(result[i].id), isFalse,
            reason: 'position $i holds recent id ${result[i].id}');
      }
      expect(_ids(result), _ids(pool));
    });

    test('anchored: position 0 keeps the current track even when recent',
        () {
      final pool = _pool(20);
      final recent = <int>[for (var i = 1; i <= 10; i++) i];
      final result = shuffle.shuffle(
        pool,
        currentIndex: 2, // id 3 is inside the recent set
        seed: 11,
        recentlyPlayedIds: recent,
      );
      expect(result.first.id, 3);
      for (var i = 1; i < AppConstants.shuffleNoRepeatWindow; i++) {
        expect(recent.contains(result[i].id), isFalse,
            reason: 'position $i holds recent id ${result[i].id}');
      }
      expect(_ids(result), _ids(pool));
    });

    test('empty recent list is a plain deterministic shuffle', () {
      final pool = _pool(15);
      final withEmpty = shuffle.shuffle(
        pool,
        currentIndex: null,
        seed: 77,
        recentlyPlayedIds: const <int>[],
      );
      final plain = shuffle.shuffle(pool, currentIndex: null, seed: 77);
      expect(
        withEmpty.map((t) => t.id),
        orderedEquals(plain.map((t) => t.id)),
      );
    });

    test('null ids never break the window pass', () {
      // Random(Seed) deterministically permutes; a track without an id is
      // skipped by the window logic (id == null guard) — it must simply not
      // crash and stay part of the permutation.
      final pool = _pool(12);
      pool[3] = _track(3).copyWith(id: null);
      final result = shuffle.shuffle(
        pool,
        currentIndex: null,
        seed: 5,
        recentlyPlayedIds: const <int>[1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12],
      );
      expect(result, hasLength(pool.length));
      expect(result.where((t) => t.id == null), hasLength(1));
    });
  });
}

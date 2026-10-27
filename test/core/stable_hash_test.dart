/// Authored, awaiting local run (Task 2-a).
///
/// Tests for `lib/core/utils/stable_hash.dart` — the FNV-1a 64-bit stable
/// hash returned as a signed base-36 string ([stableHash]) and the
/// separator-joined list variant ([hashList]).
///
/// The golden values below were computed independently with the same
/// FNV-1a 64 algorithm on 64-bit two's-complement ints (`flutter test`
/// runs on the Dart VM, so `int` is a real 64-bit int and results are
/// stable). They pin:
/// - determinism (same input → same output across calls),
/// - the exact algorithm + base-36 + SIGN encoding (several inputs hash to
///   negative 64-bit values and render with a leading `-`),
/// - UTF-8 encoding of multi-byte input.

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/utils/stable_hash.dart';

void main() {
  group('stableHash goldens', () {
    test('empty string hashes to the offset basis in base 36', () {
      expect(stableHash(''), '-shvij2mzxjob');
    });

    test('known ASCII inputs match the independent goldens', () {
      expect(stableHash('hello'), '-1e9fcrvkejlrp');
      expect(stableHash('Hello'), '1ipoiu71snp7v'); // case-sensitive
      expect(stableHash('world'), '17fwk006vjy7n');
      expect(stableHash('wavely'), 'r4hcyj7x9ber');
    });

    test('scanner-style composite input matches its golden', () {
      // The scanner hashes '$path:$fileSize:$mtimeMs'.
      expect(
        stableHash('/music/a.mp3:12345:1700000000000'),
        '-wdfp07axpf7a',
      );
    });

    test('negative results keep the leading minus sign (sign handling)',
        () {
      // Both inputs land on negative 64-bit values; the golden pins the
      // signed rendering instead of a wrap-around artifact.
      expect(stableHash('track-1'), '-1f4mksl2puzze');
      expect(stableHash('seed-0'), '-p0y0nk3ktr3b');
      expect(stableHash('track-1'), isNot(stableHash('track-2')));
    });

    test('multi-byte UTF-8 input is encoded, not code-unit hashed', () {
      expect(stableHash('naïve-🎵'), '1rdvg8zhxv6cu');
    });

    test('hashes Object.toString — an int equals its string form', () {
      expect(stableHash(42), stableHash('42'));
      expect(stableHash(42), '4cbjgjuds2sj');
    });
  });

  group('stableHash determinism & discrimination', () {
    test('repeated calls return the identical value', () {
      final first = stableHash('determinism-probe');
      final second = stableHash('determinism-probe');
      expect(first, equals(second));
      expect(first, isNotEmpty);
    });

    test('distinct inputs produce distinct hashes', () {
      final seen = <String>{};
      for (var i = 0; i < 64; i++) {
        expect(
          seen.add(stableHash('seed-$i')),
          isTrue,
          reason: 'unexpected collision at seed-$i',
        );
      }
    });

    test('adjacent inputs never collide', () {
      expect(stableHash('a'), isNot(stableHash('ab')));
      expect(stableHash('a'), isNot(stableHash('b')));
    });
  });

  group('hashList', () {
    test('is deterministic for equal lists', () {
      expect(hashList(<Object>['a', 'b']), equals(hashList(['a', 'b'])));
    });

    test('element boundaries cannot be confused with content', () {
      // ['a', 'bc'] must differ from ['ab', 'c'] — the raison d'être of
      // the separator used to join elements.
      expect(hashList(['a', 'bc']), isNot(equals(hashList(['ab', 'c']))));
      expect(
        hashList(['a', 'b', 'c']),
        isNot(equals(hashList(['a', 'bc']))),
      );
    });

    test('single-element list equals the element hash (same toString)',
        () {
      // join of one element is the element itself, so the hash matches
      // hashing that element's toString directly.
      expect(hashList(<Object>['wavely']), stableHash('wavely'));
      expect(hashList(<Object>[42]), stableHash('42'));
    });

    test('empty list hashes like the empty string', () {
      expect(hashList(<Object>[]), stableHash(''));
      expect(hashList(<Object>[]), '-shvij2mzxjob');
    });

    test('order matters', () {
      expect(hashList(['one', 'two']), isNot(equals(hashList(['two', 'one']))));
    });
  });
}

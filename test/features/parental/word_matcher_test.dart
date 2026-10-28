/// Authored, awaiting local run (Task 2-f).
///
/// [WordMatcher] contract: 15+ cases over the REAL normalization rules —
/// exact matches, case-insensitivity, leet/obfuscation variants (sh1t,
/// f*ck, spaced/hyphenated forms, `5`/`!`/`@` maps), the `*` vowel
/// wildcard, filler limits, whole-word boundaries (class ⊉ ass),
/// whitelisting, overlap removal, dedup and severity propagation. Tests
/// what the implementation actually does, including quirks (e.g. `!` is a
/// word char, so `shit!` does NOT match).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/features/parental/data/word_matcher.dart';

BlockedWordRow _row(
  String word, {
  String severity = 'moderate',
  int id = 1,
}) =>
    BlockedWordRow(
      id: id,
      word: word,
      severity: severity,
      language: null,
      addedAt: DateTime(2024, 1, 1),
    );

void main() {
  group('WordMatcher.matches', () {
    test('1. exact word match with correct offsets', () {
      final matcher = WordMatcher(words: [_row('shit')]);
      final matches = matcher.matches('turn this shit off');
      expect(matches, hasLength(1));
      expect(matches.single.word, 'shit');
      expect(matches.single.start, 10);
      expect(matches.single.end, 14); // exclusive
      expect(matches.single.severity, 'moderate');
    });

    test('2. case-insensitive on both sides', () {
      expect(
        WordMatcher(words: [_row('SHIT')]).matches('total SHIT show'),
        hasLength(1),
      );
      expect(
        WordMatcher(words: [_row('Shit')]).matches('that Shit song'),
        hasLength(1),
      );
    });

    test('3. leet digits: sh1t / 5hit match the plain word', () {
      final matcher = WordMatcher(words: [_row('shit')]);
      expect(matcher.matches('that sh1t'), hasLength(1));
      expect(matcher.matches('pure 5hit here'), hasLength(1));
    });

    test('4. f*ck matches the blocked word fuck (text `*` = vowel slot)',
        () {
      final matcher = WordMatcher(words: [_row('fuck')]);
      expect(matcher.matches('what the f*ck'), hasLength(1));
      expect(matcher.matches('fucking loud'), hasLength(1));
    });

    test('5. spaced obfuscation s h i t (fillers between letters)', () {
      final matcher = WordMatcher(words: [_row('shit')]);
      final matches = matcher.matches('s h i t');
      expect(matches, hasLength(1));
      expect(matches.single.start, 0);
      // The span covers the WHOLE obfuscated word including the last
      // letter (`t` sits at index 6), so the censor masks every char.
      expect(matches.single.end, 7);
    });

    test('6. hyphenated obfuscation f-u-c-k', () {
      final matcher = WordMatcher(words: [_row('fuck')]);
      expect(matcher.matches('f-u-c-k the system'), hasLength(1));
    });

    test('7. sh@t does NOT match blocked shit (maps to a, not i)', () {
      // The doc comment claims sh@t is caught; the actual map sends `@` →
      // `a`, so it only matches blocked words containing that letter.
      final matcher = WordMatcher(words: [_row('shit')]);
      expect(matcher.matches('that sh@t'), isEmpty);
      expect(
        WordMatcher(words: [_row('shat')]).matches('that sh@t'),
        hasLength(1),
      );
    });

    test('8. `*` inside the BLOCKED word acts as a vowel wildcard', () {
      final matcher = WordMatcher(words: [_row('sh*t')]);
      expect(matcher.matches('total shit'), hasLength(1)); // i
      expect(matcher.matches('take a shot'), hasLength(1)); // o
      expect(matcher.matches('shut it down'), hasLength(1)); // u
      expect(matcher.matches('sh-t it down'), isEmpty); // filler ≠ letter
    });

    test('9. filler budget: two fillers ok, three is too many', () {
      final matcher = WordMatcher(words: [_row('fuck')]);
      expect(matcher.matches('f  u  c  k'), hasLength(1)); // 2 fillers
      expect(matcher.matches('f   u   c   k'), isEmpty); // 3 fillers
    });

    test('10. whitelisted words are suppressed entirely', () {
      final matcher = WordMatcher(
        words: [_row('damn', id: 1), _row('hell', id: 2)],
        whitelist: <String>['damn'],
      );
      final matches = matcher.matches('damn this hell');
      expect(matches, hasLength(1));
      expect(matches.single.word, 'hell');
    });

    test('11. whole-word boundaries: class/massive never match ass', () {
      final matcher = WordMatcher(words: [_row('ass')]);
      expect(matcher.matches('the class was massive'), isEmpty);
      // Punctuation boundaries do count (non-word chars).
      expect(matcher.matches('you ass, move'), hasLength(1));
    });

    test('12. trailing `!` blocks the match (quirk: ! is a word char)',
        () {
      // `!` maps to `i` in the leet table and therefore counts as a word
      // character for boundary checks — the real implementation rejects
      // `ass!` and `shit!` today. Pinned as-is (code is truth).
      final matcher = WordMatcher(words: [_row('ass')]);
      expect(matcher.matches('you ass!'), isEmpty);
      expect(matcher.matches('you ass.'), hasLength(1)); // period is fine
    });

    test('13. multiple occurrences returned sorted by start', () {
      final matcher = WordMatcher(words: [_row('shit')]);
      final matches = matcher.matches('shit hit the fan, shit everywhere');
      expect(
        [for (final m in matches) m.start],
        <int>[0, 18],
      );
      expect(matches.every((m) => m.word == 'shit'), isTrue);
    });

    test('14. overlapping matches collapse to one (first wins)', () {
      final matcher = WordMatcher(
        words: [_row('fuck', id: 1), _row('fucking', id: 2)],
      );
      final matches = matcher.matches('fucking loud');
      // Both candidates start at 0 and overlap; exactly one survives —
      // which one is a sort-order detail, so only the count is asserted.
      expect(matches, hasLength(1));
      expect(matches.single.start, 0);
    });

    test('15. empty blocked-word list and empty text yield no matches',
        () {
      final matcher = WordMatcher(words: <BlockedWordRow>[]);
      expect(matcher.matches('anything at all shit'), isEmpty);
      expect(
        WordMatcher(words: [_row('shit')]).matches(''),
        isEmpty,
      );
    });

    test('16. severity is propagated from the blocked-word row', () {
      final matcher = WordMatcher(
        words: [_row('damn', severity: 'mild', id: 3)],
      );
      expect(matcher.matches('oh damn').single.severity, 'mild');
    });

    test('17. normalized duplicates collapse to a single target', () {
      // 'sh!t' normalizes to the same letters as 'shit' — the second row
      // is dropped, so exactly one match with the FIRST row's word.
      final matcher = WordMatcher(
        words: [_row('shit', id: 1), _row('sh!t', id: 2)],
      );
      final matches = matcher.matches('that sh!t again');
      expect(matches, hasLength(1));
      expect(matches.single.word, 'shit');
    });
  });
}

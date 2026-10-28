import 'package:wavely/data/local/db/app_database.dart';

/// One hit of a blocked word inside a text, with offsets into the ORIGINAL
/// (un-normalized) string; [end] is exclusive.
class WordMatch {
  const WordMatch({
    required this.word,
    required this.start,
    required this.end,
    required this.severity,
  });

  /// The blocked word (as stored in the `blocked_words` table) that hit.
  final String word;

  /// Inclusive start offset into the original text.
  final int start;

  /// Exclusive end offset into the original text.
  final int end;

  /// `mild` | `moderate` | `severe` — copied from the blocked-word row.
  final String severity;

  @override
  String toString() => 'WordMatch($word, $start..$end, $severity)';
}

/// Offline matcher that finds blocked words inside lyric text.
///
/// Strategy: the input text is lowered and mapped through a leet/obfuscation
/// table into a parallel character list that keeps an index map back to the
/// original positions. Each blocked word is then scanned over the normalized
/// list allowing 0-2 filler characters (space, hyphen, …) between letters,
/// which catches `s h i t`, `f-u-c-k`, `sh1t`, `f*ck` and `sh@t` alike.
/// Matches must start and end on word boundaries of the ORIGINAL text, so
/// innocent words containing a blocked word as substring (`class` ⊃ `ass`)
/// never hit. Whitelisted words are always suppressed.
///
/// Pure Dart, no external packages; fast enough for line-level lyrics
/// (~200 chars × a few dozen words).
class WordMatcher {
  WordMatcher({required List<BlockedWordRow> words, this.whitelist = const []})
      : _words = _prepare(rows: words, whitelist: whitelist);

  /// Words that must never be reported even when they would match.
  final List<String> whitelist;

  /// Normalized blocked words ready for scanning.
  final List<_Target> _words;

  static const Set<String> _vowels = <String>{'a', 'e', 'i', 'o', 'u'};

  /// Chars that may sit between the letters of an obfuscated word
  /// (`s h i t`, `f-u-c-k`); at most [_maxFillers] in a row.
  static const int _maxFillers = 2;
  static const String _fillerChars = " -_.'\u2013\u2014";

  /// Leet / obfuscation map: text char → letter. `*` means "any vowel" and
  /// is handled specially in [_charEquals].
  static const Map<String, String> _leetMap = <String, String>{
    '1': 'i',
    '!': 'i',
    '3': 'e',
    '0': 'o',
    '@': 'a',
    '4': 'a',
    '5': 's',
    r'$': 's',
  };

  /// Lowercases, applies the leet map and strips non-letter noise from a
  /// blocked word (parents may store `F*ck!` — we scan for `f?ck`).
  static String _normalizeWord(String raw) {
    final buffer = StringBuffer();
    for (final char in raw.toLowerCase().split('')) {
      final mapped = _leetMap[char];
      if (mapped != null) {
        buffer.write(mapped);
      } else if (RegExp(r'^[a-z]$').hasMatch(char) || char == '*') {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  static List<_Target> _prepare({
    required List<BlockedWordRow> rows,
    required List<String> whitelist,
  }) {
    final normalizedWhitelist = <String>{
      for (final w in whitelist) _normalizeWord(w),
    };
    final targets = <_Target>[];
    final seen = <String>{};
    for (final row in rows) {
      final normalized = _normalizeWord(row.word);
      if (normalized.isEmpty ||
          normalizedWhitelist.contains(normalized) ||
          !seen.add(normalized)) {
        continue;
      }
      targets.add(
        _Target(
          letters: normalized.split(''),
          word: row.word,
          severity: row.severity,
        ),
      );
    }
    return targets;
  }

  /// True when [textChar] (normalized) equals [wordChar] (normalized),
  /// treating `*` on either side as "any vowel".
  static bool _charEquals(String textChar, String wordChar) {
    if (wordChar == '*' || textChar == '*') {
      final other = wordChar == '*' ? textChar : wordChar;
      return other == '*' || _vowels.contains(other);
    }
    return textChar == wordChar;
  }

  /// Word-character test over the NORMALIZED list (letters plus chars that
  /// can become letters via the leet map) — used for boundary checks.
  static bool _isWordChar(String char) =>
      RegExp(r'^[a-z0-9]$').hasMatch(char) || _leetMap.containsKey(char);

  /// Finds every blocked-word occurrence in [text]. Returns matches sorted
  /// by start offset with overlaps removed (first match wins).
  List<WordMatch> matches(String text) {
    if (text.isEmpty || _words.isEmpty) {
      return const <WordMatch>[];
    }

    // Build the normalized parallel structure + index map to the original.
    final lower = text.toLowerCase();
    final norm = <String>[];
    final origIndex = <int>[];
    for (var i = 0; i < lower.length; i++) {
      final char = lower[i];
      norm.add(_leetMap[char] ?? char);
      origIndex.add(i);
    }

    final found = <WordMatch>[];
    for (final target in _words) {
      for (var start = 0; start < norm.length; start++) {
        // Word boundary: the char before the first letter must not be part
        // of a word.
        if (start > 0 && _isWordChar(norm[start - 1])) {
          continue;
        }
        final endPos = _scanFrom(norm, start, target.letters);
        if (endPos == null) {
          continue;
        }
        final lastOrig = origIndex[endPos - 1];
        // Word boundary after the last letter.
        if (lastOrig + 1 < lower.length && _isWordChar(lower[lastOrig + 1])) {
          continue;
        }
        found.add(
          WordMatch(
            word: target.word,
            start: origIndex[start],
            end: lastOrig + 1,
            severity: target.severity,
          ),
        );
      }
    }

    // Sort by start; drop any match that overlaps an earlier one so callers
    // get a deterministic, non-overlapping list.
    found.sort((a, b) => a.start.compareTo(b.start));
    final result = <WordMatch>[];
    var lastEnd = -1;
    for (final match in found) {
      if (match.start < lastEnd) {
        continue;
      }
      result.add(match);
      lastEnd = match.end;
    }
    return result;
  }

  /// Greedily matches [letters] over the normalized list starting at [start].
  /// Returns the exclusive end position in the normalized list, or null.
  static int? _scanFrom(List<String> norm, int start, List<String> letters) {
    var pos = start;
    for (var li = 0; li < letters.length; li++) {
      if (li > 0) {
        // Allow 0-2 filler chars between letters (obfuscation: `s h i t`).
        var fillers = 0;
        while (pos < norm.length &&
            fillers < _maxFillers &&
            _fillerChars.contains(norm[pos])) {
          pos++;
          fillers++;
        }
      }
      if (pos >= norm.length || !_charEquals(norm[pos], letters[li])) {
        return null;
      }
      pos++;
    }
    return pos;
  }
}

class _Target {
  const _Target({
    required this.letters,
    required this.word,
    required this.severity,
  });

  final List<String> letters;
  final String word;
  final String severity;

  String get normalized => letters.join();
}

import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:wavely/domain/entities/entities.dart';

/// Pure-Dart parser for LRC (and enhanced word-level LRC) lyrics.
///
/// Behaviour (documented decisions):
/// - Strips the UTF-8 BOM and normalizes CRLF/CR line endings.
/// - Metadata tags `[ar:] [ti:] [al:] [by:]` are captured into
///   [LyricsResult.metadata] (first occurrence wins). `[offset:]` is applied
///   to every timestamp: **effective time = stamp - offset**, i.e. a
///   positive offset shifts lyrics EARLIER, a negative one later (standard
///   LRC convention).
/// - Line stamps `[mm:ss]`, `[mm:ss.xx]`, `[mm:ss.xxx]` (fraction separator
///   `.` `:` or `,`, 1-3 fraction digits) are supported; several stamps may
///   precede one text (`[00:01.00][00:05.00]text` -> one line per stamp).
/// - Enhanced word tags `<mm:ss.xx>` inside a line become [LyricWord]s:
///   a word starts at its own tag (line start for text before the first
///   tag) and ends at the next word's start; the last word has `end: null`.
/// - Invalid/garbage bracket tags (`[00:xx]`) are skipped and the rest of
///   the line is kept.
/// - Documents WITH timestamps: untimestamped lines (plain or empty) are
///   kept as zero-start lines (empty ones render as gaps).
/// - Documents WITHOUT timestamps: the whole text collapses into a single
///   `startTime == Duration.zero` line and [LyricsResult.synced] is false.
/// - [LyricsResult.synced] is true when any timestamp tag was found; output
///   lines are stably sorted by start time.
class LrcParser {
  LrcParser._();

  static final RegExp _tagExp = RegExp(r'^\[([^\]]*)\]');
  static final RegExp _timeExp =
      RegExp(r'^(\d{1,3}):(\d{1,2})(?:[.:,](\d{1,3}))?$');
  static final RegExp _wordExp =
      RegExp(r'<(\d{1,3}):(\d{1,2})(?:[.:,](\d{1,3}))?>');
  static const Set<String> _metadataKeys = <String>{'ar', 'ti', 'al', 'by'};

  /// Parses [raw] LRC text into a [LyricsResult]. Never throws on malformed
  /// input — anything unrecognised degrades to plain text.
  static LyricsResult parse(String raw) {
    final text = raw
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    if (text.trim().isEmpty) {
      return const LyricsResult(lines: <LyricLine>[]);
    }
    final metadata = <String, String>{};
    final stamped = <LyricLine>[];
    final plain = <String>[];
    var offsetMs = 0;
    var sawTimestamp = false;

    final rawLines = text.split('\n');
    // A trailing newline is a file terminator, not a lyric gap.
    if (rawLines.isNotEmpty && rawLines.last.isEmpty) {
      rawLines.removeLast();
    }
    for (final rawLine in rawLines) {
      var rest = rawLine;
      var sawAnyTag = false;
      final stamps = <int>[];
      while (true) {
        final tag = _tagExp.firstMatch(rest);
        if (tag == null) {
          break;
        }
        sawAnyTag = true;
        final content = tag.group(1)!;
        final time = _timeExp.firstMatch(content);
        if (time != null) {
          stamps.add(_msFromGroups(time.group(1)!, time.group(2)!, time.group(3)));
          sawTimestamp = true;
        } else if (content.startsWith('offset:')) {
          final value = content.substring('offset:'.length).trim();
          offsetMs = int.tryParse(value) ?? 0;
          metadata['offset'] = value;
        } else {
          final key = content.split(':').first.trim();
          if (_metadataKeys.contains(key) && content.contains(':')) {
            final value = content.substring(key.length + 1).trim();
            metadata.putIfAbsent(key, () => value);
          }
        }
        rest = rest.substring(tag.end);
      }
      rest = rest.trim();
      if (stamps.isEmpty) {
        // Keep real text (even after invalid tags) and true empty lines as
        // gaps; drop tag-only lines such as a lone `[offset:]` header.
        if (rest.isNotEmpty || !sawAnyTag) {
          plain.add(rest);
        }
        continue;
      }
      for (final stampMs in stamps) {
        stamped.add(_buildLine(rest, stampMs, offsetMs));
      }
    }

    if (!sawTimestamp) {
      final joined = plain.join('\n');
      return LyricsResult(
        lines: <LyricLine>[
          LyricLine(startTime: Duration.zero, text: joined),
        ],
        metadata: metadata,
        synced: false,
      );
    }
    for (final textLine in plain) {
      stamped.add(LyricLine(startTime: Duration.zero, text: textLine));
    }
    // package:collection's mergeSort sorts in place and returns void.
    mergeSort<LyricLine>(
      stamped,
      compare: (a, b) => a.startTime.compareTo(b.startTime),
    );
    final sorted = stamped;
    return LyricsResult(
      lines: List<LyricLine>.unmodifiable(sorted),
      metadata: metadata,
      synced: true,
    );
  }

  static LyricLine _buildLine(String text, int stampMs, int offsetMs) {
    final effective = Duration(
      milliseconds: math.max(0, stampMs - offsetMs),
    );
    final clean = text.replaceAll(_wordExp, '');
    final wordTags = _wordExp.allMatches(text).toList();
    if (wordTags.isEmpty) {
      return LyricLine(startTime: effective, text: clean);
    }
    final segments = <(String, Duration)>[];
    var cursor = 0;
    var wordStart = effective;
    for (final tag in wordTags) {
      final segment = text.substring(cursor, tag.start);
      if (segment.isNotEmpty) {
        segments.add((segment, wordStart));
      }
      final tagMs = _msFromGroups(
        tag.group(1)!,
        tag.group(2)!,
        tag.group(3),
      );
      wordStart = Duration(
        milliseconds: math.max(0, tagMs - offsetMs),
      );
      cursor = tag.end;
    }
    final trailing = text.substring(cursor);
    if (trailing.isNotEmpty) {
      segments.add((trailing, wordStart));
    }
    final words = <LyricWord>[
      for (var i = 0; i < segments.length; i++)
        LyricWord(
          start: segments[i].$2,
          end: i + 1 < segments.length ? segments[i + 1].$2 : null,
          text: segments[i].$1,
        ),
    ];
    return LyricLine(
      startTime: effective,
      text: clean,
      words: words.isEmpty ? null : words,
    );
  }

  static int _msFromGroups(String minutes, String seconds, String? fraction) {
    var ms = 0;
    if (fraction != null && fraction.isNotEmpty) {
      if (fraction.length == 1) {
        ms = int.parse(fraction) * 100;
      } else if (fraction.length == 2) {
        ms = int.parse(fraction) * 10;
      } else {
        ms = int.parse(fraction.substring(0, 3));
      }
    }
    return int.parse(minutes) * 60000 +
        int.parse(seconds) * 1000 +
        ms;
  }
}

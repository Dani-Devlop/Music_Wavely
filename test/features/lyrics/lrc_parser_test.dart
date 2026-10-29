/// authored, awaiting local run.
///
/// Covers the real contract of `LrcParser.parse` (see the class doc in
/// lib/features/lyrics/domain/lrc_parser.dart): BOM/CRLF normalization,
/// metadata + offset tags, multi-stamp lines, malformed-tag degradation,
/// stable sort, plain-text collapse and enhanced word-level tags.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/lyrics/domain/lrc_parser.dart';

void main() {
  group('LrcParser', () {
    test('1. empty and whitespace-only documents yield no lines', () {
      for (final String raw in <String>['', '   ', '\n\n \n']) {
        final LyricsResult result = LrcParser.parse(raw);
        expect(result.lines, isEmpty);
        expect(result.synced, isFalse);
        expect(result.metadata, isEmpty);
      }
    });

    test('2. basic [mm:ss.xx] lines parse in order and stay synced', () {
      final LyricsResult result = LrcParser.parse(
        '[00:01.00]first\n[00:05.20]second\n[01:02.300]third\n',
      );
      expect(result.synced, isTrue);
      expect(result.lines, hasLength(3));
      expect(result.lines[0].startTime, const Duration(milliseconds: 1000));
      expect(result.lines[0].text, 'first');
      expect(result.lines[1].startTime, const Duration(milliseconds: 5200));
      expect(result.lines[1].text, 'second');
      expect(result.lines[2].startTime, const Duration(milliseconds: 62300));
      expect(result.lines[2].text, 'third');
      for (final LyricLine line in result.lines) {
        expect(line.words, isNull);
      }
    });

    test('3. multiple timestamps on one line expand to one line each', () {
      final LyricsResult result = LrcParser.parse(
        '[00:01.00][00:05.00]chorus\n',
      );
      expect(result.lines, hasLength(2));
      expect(result.lines[0].startTime, const Duration(seconds: 1));
      expect(result.lines[0].text, 'chorus');
      expect(result.lines[1].startTime, const Duration(seconds: 5));
      expect(result.lines[1].text, 'chorus');
    });

    test('4. fraction separators . : , and 1-3 fraction digits', () {
      final LyricsResult result = LrcParser.parse(
        '[00:01:50]a\n[00:01,250]b\n[0:01.5]c\n[00:01.12]d\n',
      );
      // Lines come back stably sorted by start time (see test 11):
      // d(1120), b(1250), then a/c (1500 each, input order on ties).
      expect(result.lines[0].startTime, const Duration(milliseconds: 1120));
      expect(result.lines[1].startTime, const Duration(milliseconds: 1250));
      expect(result.lines[2].startTime, const Duration(milliseconds: 1500));
      expect(result.lines[3].startTime, const Duration(milliseconds: 1500));
    });

    test('5. offset tag shifts lyrics earlier for positive values', () {
      final LyricsResult result = LrcParser.parse(
        '[offset:+500]\n[00:02.00]a\n',
      );
      expect(result.metadata['offset'], '+500');
      // 2000 ms stamp shifted 500 ms earlier (mirrors test 6's formula).
      expect(result.lines.single.startTime,
          const Duration(milliseconds: 1500));
    });

    test('6. negative offset shifts lyrics later', () {
      final LyricsResult result = LrcParser.parse(
        '[offset:-250]\n[00:02.00]a\n',
      );
      expect(result.lines.single.startTime, const Duration(
        milliseconds: 2250,
      ));
    });

    test('7. effective time clamps at zero for large offsets', () {
      final LyricsResult result = LrcParser.parse(
        '[offset:5000]\n[00:01.00]a\n',
      );
      expect(result.lines.single.startTime, Duration.zero);
    });

    test('8. metadata tags ar/ti/al/by captured, first occurrence wins', () {
      final LyricsResult result = LrcParser.parse(
        '[ar:First Artist][ti:Song Title]\n'
        '[ar:Second Artist][al:Album]\n'
        '[by:Transcriber]\n'
        '[00:01.00]a\n',
      );
      expect(result.metadata, <String, String>{
        'ar': 'First Artist',
        'ti': 'Song Title',
        'al': 'Album',
        'by': 'Transcriber',
      });
      expect(result.lines, hasLength(1));
    });

    test('9. unknown and malformed tags are ignored, text preserved', () {
      final LyricsResult result = LrcParser.parse(
        '[00:01.00]kept\n[00:xx]ghost text\n[ve:1]\n',
      );
      expect(result.synced, isTrue);
      // Sorted output: the invalid-tag line becomes a zero-start plain line.
      expect(result.lines, hasLength(2));
      expect(result.lines[0].startTime, Duration.zero);
      expect(result.lines[0].text, 'ghost text');
      expect(result.lines[1].startTime, const Duration(seconds: 1));
      expect(result.lines[1].text, 'kept');
    });

    test('10. tag-only lines (e.g. a lone offset header) are dropped', () {
      final LyricsResult result = LrcParser.parse(
        '[offset:500]\n[00:01.00]x\n',
      );
      expect(result.lines, hasLength(1));
      expect(result.lines.single.text, 'x');
    });

    test('11. unsorted input is stably sorted by start time', () {
      final LyricsResult result = LrcParser.parse(
        '[00:10.00]later\n[00:02.00]earlier\n[00:10.00]later twin\n',
      );
      expect(result.lines.map((LyricLine l) => l.text).toList(),
          <String>['earlier', 'later', 'later twin']);
      expect(
        result.lines[1].startTime,
        result.lines[2].startTime,
      );
    });

    test('12. CRLF and lone CR line endings are normalized', () {
      final crlf = LrcParser.parse('[00:01.00]a\r\n[00:02.00]b\r\n');
      expect(crlf.lines.map((LyricLine l) => l.text).toList(),
          <String>['a', 'b']);
      final cr = LrcParser.parse('[00:01.00]a\r[00:02.00]b\r');
      expect(cr.lines.map((LyricLine l) => l.text).toList(),
          <String>['a', 'b']);
    });

    test('13. UTF-8 BOM is stripped', () {
      final LyricsResult result = LrcParser.parse('\uFEFF[00:01.00]x\n');
      expect(result.lines.single.text, 'x');
    });

    test('14. documents without timestamps collapse to one plain line', () {
      final LyricsResult result = LrcParser.parse('line one\nline two');
      expect(result.synced, isFalse);
      expect(result.lines, hasLength(1));
      expect(result.lines.single.startTime, Duration.zero);
      expect(result.lines.single.text, 'line one\nline two');
    });

    test('15. untimestamped lines in a synced doc become zero-start lines',
        () {
      final LyricsResult result = LrcParser.parse(
        '[00:01.00]a\nplain interlude\n[00:02.00]b\n',
      );
      expect(result.synced, isTrue);
      expect(result.lines, hasLength(3));
      expect(result.lines[0].startTime, Duration.zero);
      expect(result.lines[0].text, 'plain interlude');
      expect(result.lines[1].text, 'a');
      expect(result.lines[2].text, 'b');
    });

    test('16. empty lines in a synced doc are kept as zero-start gaps', () {
      final LyricsResult result = LrcParser.parse('[00:01.00]a\n\n[00:02.00]b');
      expect(result.lines, hasLength(3));
      expect(result.lines[0].startTime, Duration.zero);
      expect(result.lines[0].text, isEmpty);
      expect(result.lines[1].text, 'a');
      expect(result.lines[2].text, 'b');
    });

    test('17. enhanced word tags produce word timings and clean text', () {
      final LyricsResult result = LrcParser.parse(
        '[00:01.00]<00:01.00>Hel<00:01.50>lo world\n',
      );
      final LyricLine line = result.lines.single;
      expect(line.text, 'Hello world');
      expect(line.words, isNotNull);
      expect(line.words, hasLength(2));
      expect(line.words![0].text, 'Hel');
      expect(line.words![0].start, const Duration(seconds: 1));
      expect(line.words![0].end, const Duration(milliseconds: 1500));
      expect(line.words![1].text, 'lo world');
      expect(line.words![1].start, const Duration(milliseconds: 1500));
      expect(line.words![1].end, isNull);
    });

    test('18. text before the first word tag starts at the line stamp', () {
      final LyricsResult result = LrcParser.parse(
        '[00:02.00]Go <00:02.50>now\n',
      );
      final LyricLine line = result.lines.single;
      expect(line.text, 'Go now');
      expect(line.words, hasLength(2));
      expect(line.words![0].start, const Duration(seconds: 2));
      expect(line.words![0].end, const Duration(milliseconds: 2500));
      expect(line.words![1].text, 'now');
      expect(line.words![1].end, isNull);
    });
  });
}

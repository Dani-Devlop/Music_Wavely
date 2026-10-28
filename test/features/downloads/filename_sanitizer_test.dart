// authored, awaiting local run.
//
// Unit tests for lib/features/downloads/domain/filename_sanitizer.dart —
// 15 cases: Windows illegal chars, control chars, trailing dots/spaces,
// reserved device names, unicode preservation, length clamping with
// extension preservation, empty fallback, extension builder.

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/downloads/domain/filename_sanitizer.dart';

void main() {
  group('sanitizeFilename (15 cases)', () {
    test('1. leaves a clean name untouched', () {
      expect(sanitizeFilename('Aurora Borealis'), 'Aurora Borealis');
    });

    test('2. replaces the Windows illegal set with underscores', () {
      expect(sanitizeFilename(r'a<b>c:"d/e\f|g?h*i'), 'a_b_c__d_e_f_g_h_i');
    });

    test('3. replaces ASCII control characters', () {
      expect(sanitizeFilename('a\x00b\x1Fc\x7Fd'), 'a_b_c_d');
    });

    test('4. trims trailing dots and spaces (Windows rule)', () {
      expect(sanitizeFilename('name...'), 'name');
      expect(sanitizeFilename('name   '), 'name');
      expect(sanitizeFilename('name . . '), 'name');
    });

    test('5. reserved device name gets a suffix (case-insensitive)', () {
      expect(sanitizeFilename('CON'), 'CON_');
      expect(sanitizeFilename('con'), 'con_');
      expect(sanitizeFilename('LPT1'), 'LPT1_');
      expect(sanitizeFilename('com9.txt'), 'com9_.txt');
    });

    test('6. a name with a dot whose stem is reserved only suffixes the stem',
        () {
      expect(sanitizeFilename('NUL.mp3'), 'NUL_.mp3');
      expect(sanitizeFilename('normal.mp3'), 'normal.mp3');
    });

    test('7. unicode is preserved', () {
      expect(sanitizeFilename('Björk – Jóga'), 'Björk – Jóga');
      expect(sanitizeFilename('日本語のタイトル'), '日本語のタイトル');
      expect(sanitizeFilename('Ω Ω'), 'Ω Ω');
    });

    test('8. long names clamp to the default 200 chars', () {
      final String out = sanitizeFilename('a' * 500);
      expect(out.length, 200);
    });

    test('9. clamping preserves a short extension', () {
      final String out = sanitizeFilename('${'a' * 250}.mp3');
      expect(out.length, 200);
      expect(out.endsWith('.mp3'), isTrue);
    });

    test('10. clamping with a long extension still preserves it', () {
      final String out = sanitizeFilename('${'a' * 250}.longextension');
      expect(out.length, 200);
      expect(out.endsWith('.longextension'), isTrue);
    });

    test('11. empty input falls back to untitled', () {
      expect(sanitizeFilename(''), 'untitled');
    });

    test('12. whitespace-only input falls back to untitled', () {
      expect(sanitizeFilename('   '), 'untitled');
    });

    test('13. illegal-only input collapses to underscores (not empty)',
        () {
      expect(sanitizeFilename('???'), '___');
    });

    test('14. custom maxLength is honoured', () {
      expect(sanitizeFilename('a' * 100, maxLength: 20).length, 20);
    });

    test('15. leading whitespace trimmed, inner kept', () {
      expect(sanitizeFilename('  spaced  name  '), 'spaced  name');
    });
  });

  group('buildTrackFilename', () {
    test('joins sanitized title and extension', () {
      expect(buildTrackFilename('Aurora', 'mp3'), 'Aurora.mp3');
      expect(buildTrackFilename('a<b', 'flac'), 'a_b.flac');
    });

    test('empty format falls back to mp3', () {
      expect(buildTrackFilename('Song', ''), 'Song.mp3');
    });

    test('extension is sanitized and bounded', () {
      expect(buildTrackFilename('Song', 'mp3?'), 'Song.mp3_');
      expect(buildTrackFilename('Song', 'averylongextension'), endsWith('averylongextension'));
    });
  });
}

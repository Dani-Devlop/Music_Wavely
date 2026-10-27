/// Authored, awaiting local run (Task 2-a).
///
/// Tests for every public extension member in `lib/core/extensions/`:
/// - `duration_x.dart` → `DurationX`: `hm`, `hmOrDash`, `digitalClock`.
/// - `string_x.dart`   → `StringX`: `isBlank`, `sanitized`.
/// - `color_x.dart`    → `ColorX`: `lighten`, `darken`, `isDark`, `toHex`
///   (plain `dart:ui` colors; no painting binding needed).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/extensions/color_x.dart';
import 'package:wavely/core/extensions/duration_x.dart';
import 'package:wavely/core/extensions/string_x.dart';

void main() {
  group('DurationX.hm', () {
    test('formats sub-minute and sub-hour durations as MM:SS', () {
      expect(Duration.zero.hm, '00:00');
      expect(const Duration(seconds: 9).hm, '00:09');
      expect(const Duration(seconds: 59).hm, '00:59');
      expect(const Duration(seconds: 60).hm, '01:00');
      expect(const Duration(seconds: 61).hm, '01:01');
      expect(const Duration(seconds: 3599).hm, '59:59');
    });

    test('formats hour-long durations as H:MM:SS with unpadded hours', () {
      expect(const Duration(seconds: 3600).hm, '1:00:00');
      expect(const Duration(seconds: 3661).hm, '1:01:01');
      expect(const Duration(seconds: 86399).hm, '23:59:59');
      expect(const Duration(seconds: 360000).hm, '100:00:00');
    });

    test('ignores sub-second components and absolute-values negatives', () {
      expect(const Duration(milliseconds: 59999).hm, '00:59');
      expect(const Duration(seconds: -3661).hm, '1:01:01');
    });
  });

  group('DurationX.hmOrDash', () {
    test('delegates to hm for positive durations', () {
      expect(const Duration(seconds: 61).hmOrDash, '01:01');
      expect(const Duration(milliseconds: 1).hmOrDash, '00:00');
    });

    test('renders an en dash for zero and negative durations', () {
      expect(Duration.zero.hmOrDash, '–');
      expect(const Duration(seconds: -1).hmOrDash, '–');
    });
  });

  group('DurationX.digitalClock', () {
    test('always renders zero-padded HH:MM:SS', () {
      expect(Duration.zero.digitalClock, '00:00:00');
      expect(const Duration(seconds: 3600).digitalClock, '01:00:00');
      expect(const Duration(seconds: 3661).digitalClock, '01:01:01');
      expect(const Duration(seconds: 359999).digitalClock, '99:59:59');
      expect(const Duration(seconds: 360000).digitalClock, '100:00:00');
    });

    test('absolute-values negatives like hm', () {
      expect(const Duration(seconds: -61).digitalClock, '00:01:01');
    });
  });

  group('StringX.isBlank', () {
    test('empty and whitespace-only strings are blank', () {
      expect(''.isBlank, isTrue);
      expect(' '.isBlank, isTrue);
      expect(' \t\n\r '.isBlank, isTrue);
    });

    test('any non-whitespace content is not blank', () {
      expect('a'.isBlank, isFalse);
      expect(' a '.isBlank, isFalse);
    });
  });

  group('StringX.sanitized', () {
    test('falls back to untitled for blank input', () {
      expect(''.sanitized, 'untitled');
      expect('   '.sanitized, 'untitled');
    });

    test('strips control characters as spaces', () {
      // \x00 and \x07 become spaces; surrounding whitespace collapses.
      expect('a\x00b\x07c'.sanitized, 'a b c');
      expect('\x7Ftitle'.sanitized, 'title');
    });

    test('removes file-name illegal characters outright', () {
      expect('a<b>c:d"e/f\\g|h?i*j'.sanitized, 'abcdefghij');
      expect('AC/DC: Back in Black'.sanitized, 'ACDC Back in Black');
    });

    test('collapses whitespace runs into single spaces and trims', () {
      expect('  a \t b\n\n c  '.sanitized, 'a b c');
    });

    test('caps the result at 120 characters', () {
      final long = 'a' * 130;
      expect(long.sanitized.length, 120);
      expect(long.sanitized, 'a' * 120);
    });

    test('returns untitled when nothing survives sanitizing', () {
      // Only illegal characters → stripped to empty → fallback.
      expect('<>:"/\\|?*'.sanitized, 'untitled');
    });

    test('leaves already-clean metadata unchanged', () {
      expect('Neon Rivers'.sanitized, 'Neon Rivers');
      expect('Radosław – Miasto (2024)'.sanitized, 'Radosław – Miasto (2024)');
    });
  });

  group('ColorX.lighten / darken', () {
    const base = Color(0xFF3366CC);

    test('amount 1.0 reaches white / black exactly', () {
      expect(base.lighten(1), Colors.white);
      expect(base.darken(1), Colors.black);
    });

    test('amount 0.0 keeps the original color', () {
      expect(base.lighten(0), base);
      expect(base.darken(0), base);
    });

    test('lighten raises and darken lowers luminance monotonically', () {
      final halfLight = base.lighten(0.5);
      final halfDark = base.darken(0.5);
      expect(halfLight, isNot(base));
      expect(halfDark, isNot(base));
      expect(halfLight.computeLuminance(), greaterThan(base.computeLuminance()));
      expect(halfDark.computeLuminance(), lessThan(base.computeLuminance()));
    });
  });

  group('ColorX.isDark', () {
    test('classifies the extremes', () {
      expect(Colors.black.isDark, isTrue);
      expect(Colors.white.isDark, isFalse);
    });

    test('mid grey (luminance ~0.216) counts as dark', () {
      expect(const Color(0xFF808080).isDark, isTrue);
    });

    test('light grey (luminance > 0.5) counts as light', () {
      // #CCCCCC linearizes to ~0.604 → light.
      expect(const Color(0xFFCCCCCC).isDark, isFalse);
    });
  });

  group('ColorX.toHex', () {
    test('renders uppercase #RRGGBB and ignores alpha', () {
      expect(const Color(0xFF3366CC).toHex, '#3366CC');
      expect(const Color(0x003366CC).toHex, '#3366CC');
      expect(const Color(0xFF000000).toHex, '#000000');
      expect(Colors.white.toHex, '#FFFFFF');
    });

    test('zero-pads low channels', () {
      expect(const Color(0xFF0A0B0C).toHex, '#0A0B0C');
      expect(const Color(0xFF010203).toHex, '#010203');
    });
  });
}

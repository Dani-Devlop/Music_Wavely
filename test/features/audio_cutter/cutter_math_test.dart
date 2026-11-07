/// Tests for the Phase 7.2 cutter math (timestamps, selection clamping,
/// ringtone validation).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/audio_cutter/data/cutter_math.dart';

void main() {
  group('parseCutTimestamp', () {
    test('parses plain seconds', () {
      expect(parseCutTimestamp('42'), const Duration(seconds: 42));
    });

    test('parses mm:ss', () {
      expect(parseCutTimestamp('01:23'), const Duration(minutes: 1, seconds: 23));
    });

    test('parses hh:mm:ss', () {
      expect(
        parseCutTimestamp('1:02:03'),
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
    });

    test('parses fractional seconds (dot and comma)', () {
      expect(
        parseCutTimestamp('01:23.500'),
        const Duration(minutes: 1, seconds: 23, milliseconds: 500),
      );
      expect(
        parseCutTimestamp('2,25'),
        const Duration(seconds: 2, milliseconds: 250),
      );
    });

    test('pads short fractions', () {
      expect(parseCutTimestamp('1.5'), const Duration(seconds: 1, milliseconds: 500));
    });

    test('rejects garbage', () {
      expect(parseCutTimestamp(''), isNull);
      expect(parseCutTimestamp('abc'), isNull);
      expect(parseCutTimestamp('1:2:3:4'), isNull);
      expect(parseCutTimestamp('-5'), isNull);
      expect(parseCutTimestamp('1.2.3'), isNull);
    });
  });

  group('formatCutTimestamp', () {
    test('formats mm:ss under an hour', () {
      expect(
        formatCutTimestamp(const Duration(minutes: 2, seconds: 5)),
        '02:05',
      );
    });

    test('formats hh:mm:ss past an hour', () {
      expect(
        formatCutTimestamp(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('truncates sub-second precision', () {
      expect(
        formatCutTimestamp(
          const Duration(minutes: 1, seconds: 2, milliseconds: 999),
        ),
        '01:02',
      );
    });

    test('formatCutTimestampMs keeps milliseconds', () {
      expect(
        formatCutTimestampMs(
          const Duration(minutes: 1, seconds: 2, milliseconds: 340),
        ),
        '01:02.340',
      );
    });
  });

  group('clampSelection', () {
    test('orders swapped endpoints', () {
      final CutSelection selection = clampSelection(
        const Duration(seconds: 10),
        const Duration(seconds: 2),
        const Duration(minutes: 1),
      );
      expect(selection.start, const Duration(seconds: 2));
      expect(selection.end, const Duration(seconds: 10));
      expect(selection.isValid, isTrue);
    });

    test('clamps into the track bounds', () {
      final CutSelection selection = clampSelection(
        const Duration(seconds: -5),
        const Duration(minutes: 5),
        const Duration(seconds: 30),
      );
      expect(selection.start, Duration.zero);
      expect(selection.end, const Duration(seconds: 30));
    });

    test('enforces the minimum length by growing the end', () {
      final CutSelection selection = clampSelection(
        const Duration(seconds: 10),
        const Duration(seconds: 10, milliseconds: 10),
        const Duration(minutes: 1),
      );
      expect(
        selection.length,
        kMinCutLength,
      );
    });

    test('grows backwards near the track end', () {
      final CutSelection selection = clampSelection(
        const Duration(seconds: 59, milliseconds: 990),
        const Duration(seconds: 59, milliseconds: 995),
        const Duration(seconds: 60),
      );
      expect(selection.end, const Duration(seconds: 60));
      expect(selection.length, kMinCutLength);
    });
  });

  group('ringtone validation', () {
    test('notification warns past the soft limit', () {
      final CutSelection long = CutSelection(
        start: Duration.zero,
        end: const Duration(seconds: 45),
      );
      expect(
        ringtoneLengthWarning(long, RingtoneKind.notification),
        isNotNull,
      );
      expect(
        ringtoneLengthWarning(long, RingtoneKind.ringtone),
        isNull,
      );
    });

    test('labels exist for every kind', () {
      for (final RingtoneKind kind in RingtoneKind.values) {
        expect(kind.label, isNotEmpty);
      }
    });
  });
}

/// Stage 4: lavfi equalizer filter-string builder (pure function).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:wavely/playback/equalizer/eq_filter.dart';
import 'package:wavely/playback/equalizer/eq_presets.dart';

void main() {
  group('buildLavfiEqualizer', () {
    test('flat vector produces the empty string (filter reset)', () {
      final String filter = buildLavfiEqualizer(
        kStandardEqFrequencies,
        List<double>.filled(10, 0),
      );
      expect(filter, '');
    });

    test('single boosted band produces one equalizer segment', () {
      final String filter = buildLavfiEqualizer(
        kStandardEqFrequencies,
        const <double>[4, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      );
      expect(filter, 'lavfi=[equalizer=f=31:t=q:w=1.41:g=4.00]');
    });

    test('flat bands are skipped, non-flat bands chained in order', () {
      final String filter = buildLavfiEqualizer(
        kStandardEqFrequencies,
        const <double>[0, -2.5, 0, 3, 0, 0, 0, 1.25, 0, 0],
      );
      expect(
        filter,
        'lavfi=[equalizer=f=62:t=q:w=1.41:g=-2.50,'
        'equalizer=f=250:t=q:w=1.41:g=3.00,'
        'equalizer=f=4000:t=q:w=1.41:g=1.25]',
      );
    });

    test('custom quality is formatted into every segment', () {
      final String filter = buildLavfiEqualizer(
        const <double>[100],
        const <double>[1],
        quality: 0.7,
      );
      expect(filter, 'lavfi=[equalizer=f=100:t=q:w=0.70:g=1.00]');
    });

    test('length mismatch never crashes (extras ignored)', () {
      expect(
        buildLavfiEqualizer(const <double>[100], const <double>[1, 2, 3]),
        'lavfi=[equalizer=f=100:t=q:w=1.41:g=1.00]',
      );
      expect(
        buildLavfiEqualizer(
          kStandardEqFrequencies,
          const <double>[1],
        ),
        'lavfi=[equalizer=f=31:t=q:w=1.41:g=1.00]',
      );
      expect(buildLavfiEqualizer(const <double>[], const <double>[1]), '');
    });

    test('a desktop-sized gain vector round-trips every band', () {
      final List<double> gains = List<double>.generate(
        kStandardEqFrequencies.length,
        (int i) => (i - 5).toDouble(),
      );
      final String filter =
          buildLavfiEqualizer(kStandardEqFrequencies, gains);
      // Index 5 is the 0 dB band (skipped) → 9 segments.
      expect(filter.startsWith('lavfi=['), isTrue);
      expect('g=0.00'.allMatches(filter), isEmpty);
      expect(','.allMatches(filter).length + 1, 9);
    });
  });
}

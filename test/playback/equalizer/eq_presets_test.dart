/// Stage 4: built-in EQ presets + gain codec/resampler.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:wavely/playback/equalizer/eq_presets.dart';

void main() {
  group('kBuiltinEqPresets', () {
    test('every preset matches the standard 10-band layout', () {
      for (final BuiltinEqPreset preset in kBuiltinEqPresets) {
        expect(
          preset.gainsDb,
          hasLength(kStandardEqFrequencies.length),
          reason: '${preset.name} band mismatch',
        );
      }
    });

    test('presets stay inside the documented gain clamp', () {
      for (final BuiltinEqPreset preset in kBuiltinEqPresets) {
        for (final double gain in preset.gainsDb) {
          expect(gain, greaterThanOrEqualTo(kEqMinGainDb));
          expect(gain, lessThanOrEqualTo(kEqMaxGainDb));
        }
      }
    });

    test('names are unique', () {
      final Set<String> names =
          kBuiltinEqPresets.map((BuiltinEqPreset p) => p.name).toSet();
      expect(names, hasLength(kBuiltinEqPresets.length));
    });

    test('frequencies are strictly ascending', () {
      for (var i = 1; i < kStandardEqFrequencies.length; i++) {
        expect(
          kStandardEqFrequencies[i],
          greaterThan(kStandardEqFrequencies[i - 1]),
        );
      }
    });
  });

  group('EqualizerGains.clamp / clampAll', () {
    test('clamps into the documented range', () {
      expect(EqualizerGains.clamp(-99), kEqMinGainDb);
      expect(EqualizerGains.clamp(99), kEqMaxGainDb);
      expect(EqualizerGains.clamp(3.5), 3.5);
      expect(EqualizerGains.clampAll(const <double>[-99, 0, 99]),
          <double>[kEqMinGainDb, 0, kEqMaxGainDb]);
    });
  });

  group('EqualizerGains.resample', () {
    test('identity when band counts match', () {
      final List<double> gains = <double>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      expect(EqualizerGains.resample(gains, 10), gains);
    });

    test('zero-pads when the engine has more bands', () {
      expect(
        EqualizerGains.resample(const <double>[1, 2], 4),
        <double>[1, 2, 0, 0],
      );
    });

    test('downsamples when the engine has fewer bands (Android=5)', () {
      final List<double> out = EqualizerGains.resample(
        const <double>[6, 5, 4, 2, 0, 0, 0, 0, 0, 0], // Bass Boost
        5,
      );
      expect(out, hasLength(5));
      for (final double gain in out) {
        expect(gain, inInclusiveRange(kEqMinGainDb, kEqMaxGainDb));
      }
      // The lowest engine band must keep the strongest bass boost.
      expect(out.first, 6.0);
    });

    test('degenerate engine (0 bands) yields an empty vector', () {
      expect(EqualizerGains.resample(const <double>[1, 2], 0), isEmpty);
    });

    test('single-band engine takes the nearest standard band', () {
      // Single band sits at the CENTER of the standard axis.
      expect(EqualizerGains.resample(const <double>[1, 2, 9, 3, 4], 1),
          <double>[9]);
    });
  });

  group('EqualizerGains.encode / decode', () {
    test('round-trips a gain vector as JSON', () {
      const List<double> gains = <double>[4, -2.5, 0, 1.25, 0, 0, 0, 0, 0, 0];
      final List<double> decoded = EqualizerGains.decode(
        EqualizerGains.encode(gains),
      );
      expect(decoded, gains);
    });

    test('malformed values degrade to an empty list', () {
      expect(EqualizerGains.decode('not json'), isEmpty);
      expect(EqualizerGains.decode('{"a": 1}'), isEmpty);
      expect(EqualizerGains.decode('42'), isEmpty);
    });

    test('non-numeric entries inside JSON are filtered out', () {
      expect(EqualizerGains.decode('[1, "2.5", 3]'), <double>[1, 3]);
    });
  });
}

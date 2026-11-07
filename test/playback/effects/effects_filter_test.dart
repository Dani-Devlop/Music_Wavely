/// Tests for the Phase 8.1 effects filter builder + state model.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/playback/effects/audio_effects.dart';
import 'package:wavely/playback/effects/effects_filter.dart';

void main() {
  group('buildLavfiEffectsChain', () {
    test('neutral state produces an empty chain', () {
      expect(
        buildLavfiEffectsChain(const EffectsFilterInput()),
        '',
      );
    });

    test('bass boost maps strength to 0..12 dB', () {
      final String half = buildLavfiEffectsChain(
        const EffectsFilterInput(bassBoost: 50),
      );
      expect(half, 'bass=g=6.00:f=100');
      final String full = buildLavfiEffectsChain(
        const EffectsFilterInput(bassBoost: 100),
      );
      expect(full, 'bass=g=12.00:f=100');
    });

    test('reverb presets map to aecho parameters', () {
      final String chain = buildLavfiEffectsChain(
        const EffectsFilterInput(reverbPreset: 'Small Room'),
      );
      expect(chain, 'aecho=0.8:0.88:40:0.5');
      // Every catalogue preset must have a mapping.
      for (final String preset in kReverbPresets) {
        expect(
          kReverbAechoParams.containsKey(preset),
          isTrue,
          reason: '$preset missing aecho params',
        );
      }
    });

    test('virtualizer widens the stereo image', () {
      expect(
        buildLavfiEffectsChain(const EffectsFilterInput(virtualizer: 50)),
        'extrastereo=m=1.50:c=0',
      );
    });

    test('balance uses constant-power gains', () {
      final String center = buildLavfiEffectsChain(
        const EffectsFilterInput(balance: 0.5),
      );
      // cos(3π/8) ≈ 0.3827, sin(3π/8) ≈ 0.9239.
      expect(center, contains('c0=0.3827*c0'));
      expect(center, contains('c1=0.9239*c1'));
    });

    test('force mono overrides balance with the mean downmix', () {
      final String chain = buildLavfiEffectsChain(
        const EffectsFilterInput(forceMono: true, balance: 0.9),
      );
      expect(chain, 'pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1');
    });

    test('composes in order: bass → reverb → virtualizer → pan', () {
      final String chain = buildLavfiEffectsChain(
        const EffectsFilterInput(
          bassBoost: 25,
          reverbPreset: 'Plate',
          virtualizer: 100,
          balance: -1,
        ),
      );
      final List<String> parts = chain.split(',');
      expect(parts, hasLength(4));
      expect(parts[0], startsWith('bass='));
      expect(parts[1], startsWith('aecho='));
      expect(parts[2], startsWith('extrastereo='));
      expect(parts[3], startsWith('pan='));
    });
  });

  group('combineAfFilters', () {
    test('joins EQ and effects and skips empties', () {
      expect(combineAfFilters('equalizer=f=60', 'bass=g=6'), contains('equalizer'));
      expect(combineAfFilters('equalizer=f=60', 'bass=g=6'),
          'equalizer=f=60,bass=g=6');
      expect(combineAfFilters('', 'bass=g=6'), 'bass=g=6');
      expect(combineAfFilters('equalizer=f=60', ''), 'equalizer=f=60');
      expect(combineAfFilters('', ''), '');
    });
  });

  group('AudioEffectsState', () {
    test('json roundtrip preserves every field', () {
      const AudioEffectsState state = AudioEffectsState(
        bassBoost: 40,
        virtualizer: 60,
        reverbPreset: 'Plate',
        balance: -0.5,
        forceMono: true,
      );
      final AudioEffectsState restored =
          AudioEffectsState.fromJson(state.toJson());
      expect(restored.bassBoost, 40);
      expect(restored.virtualizer, 60);
      expect(restored.reverbPreset, 'Plate');
      expect(restored.balance, -0.5);
      expect(restored.forceMono, isTrue);
    });

    test('corrupt json degrades to defaults', () {
      final AudioEffectsState restored = AudioEffectsState.fromJson(
        <String, Object?>{
          'bassBoost': 'not a number',
          'balance': null,
        },
      );
      expect(restored.bassBoost, 0);
      expect(restored.balance, 0);
      expect(restored.forceMono, isFalse);
    });

    test('isNeutral detects the default state', () {
      expect(const AudioEffectsState().isNeutral, isTrue);
      expect(
        const AudioEffectsState(bassBoost: 1).isNeutral,
        isFalse,
      );
    });
  });

  group('dbToVolumeMultiplier', () {
    test('converts dB to a linear factor', () {
      expect(dbToVolumeMultiplier(0), closeTo(1.0, 0.0001));
      expect(dbToVolumeMultiplier(-6), closeTo(0.5012, 0.001));
      expect(dbToVolumeMultiplier(6), closeTo(1.9953, 0.001));
      expect(dbToVolumeMultiplier(-20), closeTo(0.1, 0.0001));
    });
  });
}

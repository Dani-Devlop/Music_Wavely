/// Tests for the Phase 8.2 ReplayGain math (pure functions).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/playback/replaygain/replay_gain_math.dart';

void main() {
  group('replayGainDbFromLoudness', () {
    test('a −14 LUFS master needs −4 dB', () {
      expect(
        replayGainDbFromLoudness(-14),
        closeTo(-4.0, 0.0001),
      );
    });

    test('a −24 LUFS master needs +6 dB', () {
      expect(
        replayGainDbFromLoudness(-24),
        closeTo(6.0, 0.0001),
      );
    });

    test('the reference loudness itself needs 0 dB', () {
      expect(replayGainDbFromLoudness(-18), closeTo(0.0, 0.0001));
    });
  });

  group('albumGainFromLoudnesses', () {
    test('energy-combines two tracks (sum is louder than either)', () {
      // Track A: −14 LUFS, track B: −24 LUFS. Power summation makes the
      // combined album LOUDER than the loudest member (−14), by nearly
      // the full −14-vs−−24 gap scaled by A's dominance.
      final double gain = albumGainFromLoudnesses(<double>[-14, -24]);
      final double combinedLufs = -18 - gain;
      expect(combinedLufs, greaterThan(-14.0));
      expect(combinedLufs, lessThan(-13.0));
    });

    test('two identical tracks combine +3.01 dB louder', () {
      final double album = albumGainFromLoudnesses(<double>[-16, -16]);
      final double combinedLufs = -18 - album;
      expect(combinedLufs, closeTo(-16 + 3.0103, 0.001));
    });

    test('empty input degrades to 0 dB', () {
      expect(albumGainFromLoudnesses(<double>[]), 0);
    });
  });

  group('pre-amp + clip safety', () {
    test('applyPreamp adds on top', () {
      expect(applyPreamp(-4, 1.5), -2.5);
    });

    test('clipSafeGain caps at full scale', () {
      // Peak 0.5 (−6.02 dBFS): max gain without clipping is +6.02 dB.
      expect(clipSafeGain(10, 0.5), closeTo(6.0206, 0.001));
      // Quiet peak → generous cap; the requested gain survives.
      expect(clipSafeGain(-3, 0.1), -3);
      // Unknown peak → unchanged.
      expect(clipSafeGain(4, null), 4);
    });
  });

  group('replayGainMultiplier', () {
    test('off mode always yields 1.0', () {
      expect(
        replayGainMultiplier(mode: ReplayGainMode.off, trackGainDb: -4),
        1.0,
      );
    });

    test('track mode applies the track gain', () {
      final double multiplier = replayGainMultiplier(
        mode: ReplayGainMode.track,
        trackGainDb: -20,
      );
      expect(multiplier, closeTo(0.1, 0.0001));
    });

    test('album mode prefers the album gain, falls back to track', () {
      final double withAlbum = replayGainMultiplier(
        mode: ReplayGainMode.album,
        trackGainDb: -20,
        albumGainDb: -10,
      );
      expect(withAlbum, closeTo(0.3162, 0.001));
      final double fallback = replayGainMultiplier(
        mode: ReplayGainMode.album,
        trackGainDb: -20,
      );
      expect(fallback, closeTo(0.1, 0.0001));
    });

    test('missing measurements keep unity volume', () {
      expect(
        replayGainMultiplier(mode: ReplayGainMode.track),
        1.0,
      );
    });

    test('pre-amp scales the multiplier', () {
      final double boosted = replayGainMultiplier(
        mode: ReplayGainMode.track,
        trackGainDb: -20,
        preampDb: 6,
      );
      expect(boosted, closeTo(0.1 * 1.9953, 0.001));
    });

    test('clip cap prevents over-unity from loud peaks', () {
      final double capped = replayGainMultiplier(
        mode: ReplayGainMode.track,
        trackGainDb: 20,
        peakLinear: 1.0,
      );
      // Peak 1.0 → max gain 0 dB → multiplier 1.
      expect(capped, closeTo(1.0, 0.0001));
    });
  });

  group('parseEbur128Log', () {
    test('parses the summary block', () {
      const String log = '''
[Parsed_ebur128_0 @ 0x0] Summary:

  Integrated loudness:
    I:        -14.2 LUFS
    Threshold: -24.3 LUFS

  Loudness range:
    LRA:       7.1 LU

  True peak:
    Peak:      -0.8 dBFS
''';
      final LoudnessMeasurement? measurement = parseEbur128Log(log);
      expect(measurement, isNotNull);
      expect(measurement!.integratedLufs, closeTo(-14.2, 0.0001));
      expect(measurement.peakLinear, closeTo(0.9120, 0.001));
    });

    test('falls back to streaming I: lines', () {
      const String log = '[Parsed_ebur128] t: 1 I: -13.9 LUFS';
      final LoudnessMeasurement? measurement = parseEbur128Log(log);
      expect(measurement, isNotNull);
      expect(measurement!.integratedLufs, closeTo(-13.9, 0.0001));
      expect(measurement.peakLinear, isNull);
    });

    test('garbage yields null', () {
      expect(parseEbur128Log(''), isNull);
      expect(parseEbur128Log('no loudness here'), isNull);
    });
  });

  group('mode codec', () {
    test('roundtrips all modes; unknowns degrade to off', () {
      for (final ReplayGainMode mode in ReplayGainMode.values) {
        expect(replayGainModeFromName(replayGainModeName(mode)), mode);
      }
      expect(replayGainModeFromName('nonsense'), ReplayGainMode.off);
      expect(replayGainModeFromName('TRACK'), ReplayGainMode.track);
    });
  });
}

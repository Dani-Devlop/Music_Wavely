/// ReplayGain computation (Phase 8.2) — pure functions over ebur128
/// loudness measurements.
///
/// Reference: ReplayGain 1.0 places an 89 dB SPL-calibrated pink-noise
/// reference at −14 LUFS? No — RG 1.0 predates LUFS; the accepted mapping
/// (used by loudgain, mp3gain and Musicolet-class players) is:
///
///     track_gain = RG_REFERENCE_LUFS − integrated_loudness_LUFS
///
/// with RG_REFERENCE_LUFS = −18 (i.e. RG 1.0's 89 dB reference expressed
/// in LUFS). Album gain follows the same formula over the energy-weighted
/// combination of every track in the album.
library;

import 'dart:math' as math;

import 'package:wavely/playback/effects/effects_filter.dart';

/// RG 1.0 reference loudness in LUFS (−18).
const double kReplayGainReferenceLufs = -18.0;

/// Default pre-amp (dB) applied on top of the computed gain.
const double kDefaultPreampDb = 0.0;

/// How ReplayGain is applied during playback.
enum ReplayGainMode { off, track, album }

/// Parses the persisted mode string; unknown values degrade to off.
ReplayGainMode replayGainModeFromName(String name) =>
    switch (name.toLowerCase()) {
      'track' => ReplayGainMode.track,
      'album' => ReplayGainMode.album,
      _ => ReplayGainMode.off,
    };

/// Display/persistence name of [mode].
String replayGainModeName(ReplayGainMode mode) => switch (mode) {
      ReplayGainMode.track => 'track',
      ReplayGainMode.album => 'album',
      ReplayGainMode.off => 'off',
    };

/// Track gain (dB) for one integrated loudness measurement.
double replayGainDbFromLoudness(
  double integratedLufs, {
  double referenceLufs = kReplayGainReferenceLufs,
}) =>
    referenceLufs - integratedLufs;

/// Album gain (dB): energy-combines per-track loudness values
/// (sum of linear powers, back to LUFS) and applies the reference.
double albumGainFromLoudnesses(
  List<double> trackLoudnessLufs, {
  double referenceLufs = kReplayGainReferenceLufs,
}) {
  if (trackLoudnessLufs.isEmpty) {
    return 0;
  }
  double powerSum = 0;
  for (final double lufs in trackLoudnessLufs) {
    powerSum += math.pow(10.0, (lufs + 0.691) / 10.0).toDouble();
  }
  final double combined = 10 * math.log(powerSum) / math.ln10 - 0.691;
  return replayGainDbFromLoudness(combined, referenceLufs: referenceLufs);
}

/// Applies the pre-amp on top of a computed gain.
double applyPreamp(double gainDb, double preampDb) => gainDb + preampDb;

/// Clip-safe cap: the largest gain that keeps the peak at/below full
/// scale (`−20·log10(peak)`), or [gainDb] itself when no peak is known.
double clipSafeGain(double gainDb, double? peakLinear) {
  final double? peak = peakLinear;
  if (peak == null || peak <= 0) {
    return gainDb;
  }
  final double maxGain = -20 * math.log(peak) / math.ln10;
  return math.min(gainDb, maxGain);
}

/// Volume multiplier (0..∞) for a gain in dB — what the engine's
/// setVolume receives (as a factor over the user's base volume).
double volumeMultiplierForGain(double gainDb) =>
    dbToVolumeMultiplier(gainDb);

/// Parsed ebur128 summary.
class LoudnessMeasurement {
  const LoudnessMeasurement({required this.integratedLufs, this.peakLinear});

  final double integratedLufs;

  /// True peak as a linear 0..1 value, when the log carried one.
  final double? peakLinear;
}

/// Parses an FFmpeg `ebur128` summary log.
///
/// Recognizes the summary block:
/// ```text
/// [Parsed_ebur128...] Summary:
///
///   Integrated loudness:
///     I:        -14.2 LUFS
///     Threshold: -24.3 LUFS
///
///   Loudness range:
///     LRA:       7.1 LU
/// ...
///   True peak:
///     Peak:      -0.8 dBFS
/// ```
/// Falls back to the first `I: <number> LUFS` anywhere in [log] (the
/// momentary lines update continuously; the summary is preferred).
LoudnessMeasurement? parseEbur128Log(String log) {
  if (log.isEmpty) {
    return null;
  }
  final RegExp integratedPattern = RegExp(
    r'I:\s*(-?\d+(?:\.\d+)?)\s*LUFS',
    caseSensitive: false,
  );
  final RegExp peakPattern = RegExp(
    r'Peak:\s*(-?\d+(?:\.\d+)?)\s*dBFS',
    caseSensitive: false,
  );

  double? integrated;
  double? peak;
  // Prefer the summary section when present: take the LAST matches (the
  // summary follows the streaming lines).
  for (final RegExpMatch match in integratedPattern.allMatches(log)) {
    integrated = double.tryParse(match.group(1)!);
  }
  for (final RegExpMatch match in peakPattern.allMatches(log)) {
    peak = double.tryParse(match.group(1)!);
  }
  if (integrated == null) {
    return null;
  }
  return LoudnessMeasurement(
    integratedLufs: integrated,
    peakLinear:
        peak == null ? null : math.pow(10.0, peak / 20.0).toDouble(),
  );
}

/// Final volume multiplier for one playback step:
/// mode → gain selection → pre-amp → clip cap → multiplier.
double replayGainMultiplier({
  required ReplayGainMode mode,
  double? trackGainDb,
  double? albumGainDb,
  double? peakLinear,
  double preampDb = kDefaultPreampDb,
}) {
  switch (mode) {
    case ReplayGainMode.off:
      return 1.0;
    case ReplayGainMode.track:
      final double? gain = trackGainDb;
      if (gain == null) {
        return 1.0;
      }
      return volumeMultiplierForGain(
        clipSafeGain(applyPreamp(gain, preampDb), peakLinear),
      );
    case ReplayGainMode.album:
      final double? gain = albumGainDb ?? trackGainDb;
      if (gain == null) {
        return 1.0;
      }
      return volumeMultiplierForGain(
        clipSafeGain(applyPreamp(gain, preampDb), peakLinear),
      );
  }
}

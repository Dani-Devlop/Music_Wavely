/// Pure lavfi filter-chain builder for the Phase 8 effects set.
///
/// Desktop (media_kit) applies BassBoost / Virtualizer / Reverb / Balance /
/// Force-mono through one mpv `af` property. This module owns the
/// string construction so it can be unit-tested without a player.
library;

import 'dart:math' as math;

/// Bass boost ceiling (dB at strength 100).
const double kBassBoostMaxDb = 12.0;

/// Standard 5-band equalizer frequencies (Musicolet-parity layout).
const List<double> kFiveBandFrequencies = <double>[
  60,
  230,
  910,
  3600,
  14000,
];

/// Reverb presets mirroring Android's PresetReverb catalogue.
const List<String> kReverbPresets = <String>[
  'Small Room',
  'Medium Room',
  'Large Room',
  'Medium Hall',
  'Large Hall',
  'Plate',
];

/// aecho parameters per reverb preset (gain_in:gain_out:delays:decays).
const Map<String, String> kReverbAechoParams = <String, String>{
  'Small Room': '0.8:0.88:40:0.5',
  'Medium Room': '0.8:0.9:100:0.4',
  'Large Room': '0.8:0.9:220:0.3',
  'Medium Hall': '0.8:0.9:300:0.25',
  'Large Hall': '0.8:0.9:500:0.2',
  'Plate': '0.9:0.85:60:0.6',
};

/// Inputs bundle for [buildLavfiEffectsChain].
class EffectsFilterInput {
  const EffectsFilterInput({
    this.bassBoost = 0,
    this.virtualizer = 0,
    this.reverbPreset = '',
    this.balance = 0,
    this.forceMono = false,
  });

  /// 0..100.
  final int bassBoost;

  /// 0..100.
  final int virtualizer;

  /// One of [kReverbPresets], or '' for off.
  final String reverbPreset;

  /// −1 (full left) … +1 (full right).
  final double balance;

  /// Mono downmix (overrides balance).
  final bool forceMono;
}

/// Builds the effects-only lavfi chain (no EQ). Empty string when every
/// effect is neutral, so callers can skip the `af` write entirely.
String buildLavfiEffectsChain(EffectsFilterInput input) {
  final List<String> filters = <String>[];

  if (input.bassBoost > 0) {
    final double gainDb =
        (input.bassBoost.clamp(0, 100) / 100.0) * kBassBoostMaxDb;
    filters.add('bass=g=${gainDb.toStringAsFixed(2)}:f=100');
  }

  final String? reverb = input.reverbPreset.isEmpty
      ? null
      : kReverbAechoParams[input.reverbPreset];
  if (reverb != null) {
    filters.add('aecho=$reverb');
  }

  if (input.virtualizer > 0) {
    final double m = 1 + (input.virtualizer.clamp(0, 100) / 100.0);
    filters.add('extrastereo=m=${m.toStringAsFixed(2)}:c=0');
  }

  if (input.forceMono) {
    filters.add('pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1');
  } else if (input.balance.abs() > 0.001) {
    final double b = input.balance.clamp(-1.0, 1.0);
    // Constant-power pan: left gain cos((b+1)·π/4), right gain sin.
    final double left = math.cos((b + 1) * math.pi / 4);
    final double right = math.sin((b + 1) * math.pi / 4);
    filters.add(
      'pan=stereo|c0=${left.toStringAsFixed(4)}*c0|'
      'c1=${right.toStringAsFixed(4)}*c1',
    );
  }

  return filters.join(',');
}

/// Joins the EQ chain and the effects chain into one `af` value
/// (empty when both are empty — the engine then clears the property).
String combineAfFilters(String eqChain, String effectsChain) {
  final List<String> parts = <String>[
    if (eqChain.isNotEmpty) eqChain,
    if (effectsChain.isNotEmpty) effectsChain,
  ];
  return parts.join(',');
}

/// Volume multiplier for a gain in dB: `10^(dB/20)` (ReplayGain +
/// pre-amp application, Phase 8.2).
double dbToVolumeMultiplier(double gainDb) =>
    math.pow(10.0, gainDb / 20.0).toDouble();

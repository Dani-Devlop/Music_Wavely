/// Built-in equalizer presets and the JSON codec used to persist user
/// presets in the `eq_presets` Drift table (Stage 4, feature 2.2).
library;

import 'dart:convert';

/// Canonical 10-band layout (ISO octave centers). The desktop engine maps
/// these 1:1; the mobile AndroidEqualizer has a device-reported band count
/// (usually 5) and [EqualizerGains.resample] adapts the layout to it.
const List<double> kStandardEqFrequencies = <double>[
  31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
];

/// Per-band gain clamp shared by engines, presets and the persistence
/// codec.
const double kEqMinGainDb = -12;
const double kEqMaxGainDb = 12;

/// One named, immutable gain vector.
class BuiltinEqPreset {
  /// Creates a preset; [gainsDb] must match [kStandardEqFrequencies].
  const BuiltinEqPreset({required this.name, required this.gainsDb});

  /// Stable preset name (also used as the "builtin:" lookup key).
  final String name;

  /// Gain vector (dB) over [kStandardEqFrequencies].
  final List<double> gainsDb;
}

/// Built-in presets shipped with the app (never stored in the database —
/// user presets live in `eq_presets` instead).
const List<BuiltinEqPreset> kBuiltinEqPresets = <BuiltinEqPreset>[
  BuiltinEqPreset(name: 'Flat', gainsDb: <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  BuiltinEqPreset(
    name: 'Bass Boost',
    gainsDb: <double>[6, 5, 4, 2, 0, 0, 0, 0, 0, 0],
  ),
  BuiltinEqPreset(
    name: 'Vocal Boost',
    gainsDb: <double>[-2, -1, 0, 2, 4, 4, 3, 1, 0, 0],
  ),
  BuiltinEqPreset(
    name: 'Treble Boost',
    gainsDb: <double>[0, 0, 0, 0, 0, 0, 2, 4, 5, 6],
  ),
  BuiltinEqPreset(
    name: 'Rock',
    gainsDb: <double>[5, 4, 2, -1, -2, 0, 2, 3, 4, 4],
  ),
  BuiltinEqPreset(
    name: 'Electronic',
    gainsDb: <double>[5, 4, 1, 0, -2, 1, 0, 2, 4, 5],
  ),
];

/// Helpers around gain vectors: clamping, layout adaptation and the
/// `eq_presets.bands_json` codec.
abstract final class EqualizerGains {
  /// Clamps [gain] into [kEqMinGainDb, kEqMaxGainDb].
  static double clamp(double gain) =>
      gain.clamp(kEqMinGainDb, kEqMaxGainDb).toDouble();

  /// Clamps every entry of [gains].
  static List<double> clampAll(List<double> gains) => gains.map(clamp).toList();

  /// Adapts a gain vector authored over the standard 10-band layout to an
  /// engine with [bandCount] bands:
  ///
  /// - `bandCount >= gains.length` → zero-padded tail,
  /// - `bandCount <  gains.length` → log-spaced downsample over the
  ///   frequency axis (each engine band takes the standard band whose
  ///   center is closest to `kStandardEqFrequencies` rescaled into the
  ///   engine's range).
  ///
  /// The engine band count is always respected — a mismatch can never
  /// produce an out-of-range band index.
  static List<double> resample(List<double> gains, int bandCount) {
    if (bandCount <= 0) {
      return const <double>[];
    }
    if (bandCount == gains.length) {
      return List<double>.of(gains);
    }
    if (bandCount > gains.length) {
      return <double>[
        ...gains,
        ...List<double>.filled(bandCount - gains.length, 0),
      ];
    }
    final List<double> out = <double>[];
    for (var i = 0; i < bandCount; i++) {
      // Position of this engine band inside the standard layout's
      // normalized [0, 1] frequency axis, then the nearest standard band.
      final double pos = bandCount <= 1
          ? 0
          : i * (gains.length - 1) / (bandCount - 1);
      final int nearest =
          (pos.round()).clamp(0, gains.length - 1).toInt();
      out.add(gains[nearest]);
    }
    return out;
  }

  /// Encodes a gain vector for the `bands_json` column (JSON array).
  static String encode(List<double> gains) =>
      jsonEncode(gains.map((double g) => g.toStringAsFixed(2)).toList());

  /// Decodes a `bands_json` column value. Malformed values degrade to an
  /// empty list (same fault-tolerance as `NewsCategoryCodec`).
  static List<double> decode(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<num>()
            .map((num v) => v.toDouble())
            .toList(growable: false);
      }
    } on Object {
      // Fall through to the empty default.
    }
    return const <double>[];
  }
}

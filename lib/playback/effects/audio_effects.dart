/// Capability interface + state model for the Phase 8 audio effects.
///
/// Mirrors the [EqualizerControl] pattern: a separate interface engines
/// opt into, so `PlaybackEngine` and every existing fake stay untouched.
///
/// Implementations:
/// - `DesktopPlaybackEngine` (media_kit) — pushes the whole effects set
///   through one mpv `af` lavfi chain (`effects_filter.dart`).
/// - `MobilePlaybackEngine` — not implemented (just_audio exposes no
///   bassboost/virtualizer/reverb API; the Android route would be a
///   platform channel, and this repository currently ships no Android
///   target). The capability reports `false` and the controller degrades.
library;

import 'package:wavely/playback/effects/effects_filter.dart';

/// Snapshot of the whole effects setup.
class AudioEffectsState {
  const AudioEffectsState({
    this.bassBoost = 0,
    this.virtualizer = 0,
    this.reverbPreset = '',
    this.balance = 0,
    this.forceMono = false,
  });

  /// BassBoost strength 0..100.
  final int bassBoost;

  /// Virtualizer (surround) strength 0..100.
  final int virtualizer;

  /// One of [kReverbPresets] or '' (off).
  final String reverbPreset;

  /// Balance −1 … +1.
  final double balance;

  /// Force mono downmix.
  final bool forceMono;

  bool get isNeutral =>
      bassBoost == 0 &&
      virtualizer == 0 &&
      reverbPreset.isEmpty &&
      balance.abs() <= 0.001 &&
      !forceMono;

  AudioEffectsState copyWith({
    int? bassBoost,
    int? virtualizer,
    String? reverbPreset,
    double? balance,
    bool? forceMono,
  }) =>
      AudioEffectsState(
        bassBoost: bassBoost ?? this.bassBoost,
        virtualizer: virtualizer ?? this.virtualizer,
        reverbPreset: reverbPreset ?? this.reverbPreset,
        balance: balance ?? this.balance,
        forceMono: forceMono ?? this.forceMono,
      );

  /// JSON-ready map (per-device profile persistence).
  Map<String, Object?> toJson() => <String, Object?>{
        'bassBoost': bassBoost,
        'virtualizer': virtualizer,
        'reverbPreset': reverbPreset,
        'balance': balance,
        'forceMono': forceMono,
      };

  /// Restores from [json]; unknown shapes fall back to defaults.
  factory AudioEffectsState.fromJson(Map<String, Object?> json) =>
      AudioEffectsState(
        bassBoost: _asInt(json['bassBoost']) ?? 0,
        virtualizer: _asInt(json['virtualizer']) ?? 0,
        reverbPreset: json['reverbPreset'] is String
            ? json['reverbPreset']! as String
            : '',
        balance: _asDouble(json['balance']) ?? 0,
        forceMono: json['forceMono'] is bool
            ? json['forceMono']! as bool
            : false,
      );

  static int? _asInt(Object? value) =>
      value is int ? value : (value is num ? value.toInt() : null);

  static double? _asDouble(Object? value) =>
      value is double ? value : (value is num ? value.toDouble() : null);
}

/// Opt-in effects capability (see the library doc).
abstract class AudioEffectsControl {
  /// Whether the engine can apply effects on this platform.
  bool get effectsAvailable;

  /// Applies the whole effects state in one push. Returns `true` on
  /// success; never throws.
  Future<bool> applyEffects(AudioEffectsState state);
}

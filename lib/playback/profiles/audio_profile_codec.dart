/// `AudioSettingsState` ↔ Drift `audio_profiles` codec (Phase 8.4).
library;

import 'dart:convert';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/audio_profiles_dao.dart';
import 'package:wavely/playback/effects/audio_effects.dart';
import 'package:wavely/playback/replaygain/replay_gain_math.dart';
import 'package:wavely/playback/transitions/transition_planner.dart';

/// Full sound setup remembered per output device.
class AudioSettingsState {
  const AudioSettingsState({
    this.eqEnabled = true,
    this.eqGains = const <double>[0, 0, 0, 0, 0],
    this.eqPresetKey = '',
    this.effects = const AudioEffectsState(),
    this.replayGainMode = ReplayGainMode.off,
    this.replayGainPreampDb = 0,
    this.crossfadeSeconds = 0,
    this.gapless = true,
  });

  final bool eqEnabled;

  /// Per-band gains (dB) over the standard 5-band layout.
  final List<double> eqGains;

  /// Active preset key (`builtin:Rock` or a user preset name); empty =
  /// custom/manual.
  final String eqPresetKey;

  final AudioEffectsState effects;
  final ReplayGainMode replayGainMode;
  final double replayGainPreampDb;
  final int crossfadeSeconds;
  final bool gapless;

  TransitionConfig get transitions => TransitionConfig.sanitize(
        crossfadeSeconds: crossfadeSeconds,
        gapless: gapless,
      );

  AudioSettingsState copyWith({
    bool? eqEnabled,
    List<double>? eqGains,
    String? eqPresetKey,
    AudioEffectsState? effects,
    ReplayGainMode? replayGainMode,
    double? replayGainPreampDb,
    int? crossfadeSeconds,
    bool? gapless,
  }) =>
      AudioSettingsState(
        eqEnabled: eqEnabled ?? this.eqEnabled,
        eqGains: eqGains ?? this.eqGains,
        eqPresetKey: eqPresetKey ?? this.eqPresetKey,
        effects: effects ?? this.effects,
        replayGainMode: replayGainMode ?? this.replayGainMode,
        replayGainPreampDb: replayGainPreampDb ?? this.replayGainPreampDb,
        crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
        gapless: gapless ?? this.gapless,
      );
}

/// Row ↔ state conversion helpers.
abstract final class AudioProfileCodec {
  /// Builds the state from a stored row.
  static AudioSettingsState fromRow(AudioProfileRow row) {
    List<double> gains;
    try {
      final Object? decoded = jsonDecode(row.eqGainsJson);
      gains = decoded is List
          ? <double>[
              for (final Object? value in decoded)
                value is num ? value.toDouble() : 0.0,
            ]
          : const <double>[];
    } on Object {
      gains = const <double>[];
    }
    return AudioSettingsState(
      eqEnabled: row.eqEnabled,
      eqGains: gains,
      eqPresetKey: row.eqPresetKey,
      effects: AudioEffectsState(
        bassBoost: row.bassBoost,
        virtualizer: row.virtualizer,
        reverbPreset: row.reverbPreset,
        balance: row.balance,
        forceMono: row.forceMono,
      ),
      replayGainMode: replayGainModeFromName(row.replayGainMode),
      replayGainPreampDb: row.replayGainPreampDb,
      crossfadeSeconds: row.crossfadeSeconds,
      gapless: row.gapless,
    );
  }

  /// Column values for an upsert.
  static AudioProfileValues toValues(AudioSettingsState state) =>
      AudioProfileValues(
        eqEnabled: state.eqEnabled,
        eqGainsJson: encodeGains(state.eqGains),
        eqPresetKey: state.eqPresetKey,
        bassBoost: state.effects.bassBoost,
        virtualizer: state.effects.virtualizer,
        reverbPreset: state.effects.reverbPreset,
        balance: state.effects.balance,
        forceMono: state.effects.forceMono,
        replayGainMode: replayGainModeName(state.replayGainMode),
        replayGainPreampDb: state.replayGainPreampDb,
        crossfadeSeconds: state.crossfadeSeconds,
        gapless: state.gapless,
      );

  /// Gain vector → canonical JSON array (fixed 5 slots).
  static String encodeGains(List<double> gains) => jsonEncode(<double>[
        for (var i = 0; i < 5; i++)
          i < gains.length ? _round(gains[i]) : 0.0,
      ]);

  static double _round(double value) =>
      (value * 100).roundToDouble() / 100;
}

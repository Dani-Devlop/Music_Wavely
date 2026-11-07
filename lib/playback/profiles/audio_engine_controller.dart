/// Per-output-device audio engine controller (Phase 8.1 + 8.4).
///
/// Owns the full sound setup ([AudioSettingsState]) for the *active*
/// output device:
/// - EQ: pushes gains through [EqualizerControl] (engine capability).
/// - Effects: BassBoost / Virtualizer / Reverb / Balance / Force-mono via
///   [AudioEffectsControl].
/// - Persisting every change into the `audio_profiles` table keyed by
///   `(deviceKey, outputDeviceId)` and auto-switching profiles when the
///   output device changes.
///
/// ReplayGain mode + pre-amp live in the same profile; their playback
/// application lives in `replay_gain_playback.dart`, crossfade/gapless in
/// the transition coordinator — both read the state through providers
/// exposed here.
library;

import 'dart:async';

import 'package:flutter_riverpod/legacy.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/playback/effects/audio_effects.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/equalizer/eq_presets.dart';
import 'package:wavely/playback/equalizer/equalizer_control.dart';
import 'package:wavely/playback/equalizer/equalizer_controller.dart'
    show deviceIdProvider;
import 'package:wavely/playback/profiles/audio_profile_codec.dart';
import 'package:wavely/playback/profiles/output_device_tracker.dart';
import 'package:wavely/playback/replaygain/replay_gain_math.dart';
import 'package:wavely/playback/transitions/transition_planner.dart';

/// Controller state: the active profile + bookkeeping.
class AudioEngineState {
  const AudioEngineState({
    this.settings = const AudioSettingsState(),
    this.outputDeviceId = kDefaultOutputDeviceId,
    this.outputDeviceLabel = 'Default output',
    this.effectsSupported = false,
    this.eqSupported = false,
    this.ready = false,
  });

  final AudioSettingsState settings;
  final String outputDeviceId;
  final String outputDeviceLabel;
  final bool effectsSupported;
  final bool eqSupported;
  final bool ready;

  AudioEngineState copyWith({
    AudioSettingsState? settings,
    String? outputDeviceId,
    String? outputDeviceLabel,
    bool? effectsSupported,
    bool? eqSupported,
    bool? ready,
  }) =>
      AudioEngineState(
        settings: settings ?? this.settings,
        outputDeviceId: outputDeviceId ?? this.outputDeviceId,
        outputDeviceLabel: outputDeviceLabel ?? this.outputDeviceLabel,
        effectsSupported: effectsSupported ?? this.effectsSupported,
        eqSupported: eqSupported ?? this.eqSupported,
        ready: ready ?? this.ready,
      );
}

/// Engine accessor indirection (avoids importing the provider here in a
/// cycle-prone way; the composition root supplies a read closure).
typedef PlaybackEngineRef = Object? Function();

/// Drives the per-device audio engine settings.
class AudioEngineController extends StateNotifier<AudioEngineState> {
  AudioEngineController({
    required AppDatabase db,
    required Future<String> deviceKeyFuture,
    required PlaybackEngineRef engineRef,
    OutputDeviceTracker? outputDeviceTracker,
  })  : _db = db,
        _deviceKeyFuture = deviceKeyFuture,
        _engineRef = engineRef,
        _tracker = outputDeviceTracker ?? const DefaultOutputDeviceTracker(),
        super(const AudioEngineState());

  final AppDatabase _db;
  final Future<String> _deviceKeyFuture;
  final PlaybackEngineRef _engineRef;
  final OutputDeviceTracker _tracker;

  StreamSubscription<String>? _deviceSub;
  String? _deviceKey;
  bool _disposed = false;

  /// Loads the profile for the current output device and applies it.
  Future<void> init() async {
    _deviceKey = await _deviceKeyFuture;
    final String outputId = await _tracker.currentOutputDeviceId();
    await _loadAndApply(outputId);
    _deviceSub = _tracker.deviceChanges.listen(
      (String newDevice) {
        // Auto-switch on device change (Musicolet per-output profiles).
        unawaited(_loadAndApply(newDevice));
      },
      onError: (Object _, StackTrace __) {},
    );
  }

  Future<void> _loadAndApply(String outputId) async {
    final String? deviceKey = _deviceKey;
    if (deviceKey == null) {
      return;
    }
    final AudioProfileRow? row =
        await _db.audioProfilesDao.byOutput(deviceKey, outputId);
    final AudioSettingsState settings = row == null
        ? const AudioSettingsState()
        : AudioProfileCodec.fromRow(row);
    final String label = await _tracker.deviceLabel(outputId);
    if (_disposed) {
      return;
    }
    state = state.copyWith(
      settings: settings,
      outputDeviceId: outputId,
      outputDeviceLabel: label,
      ready: true,
    );
    await _applyToEngine(settings);
    _detectCapabilities();
  }

  void _detectCapabilities() {
    final Object? engine = _engineRef();
    state = state.copyWith(
      eqSupported: engine is EqualizerControl && engine.equalizerAvailable,
      effectsSupported: engine is AudioEffectsControl &&
          engine.effectsAvailable,
    );
  }

  /// Pushes EQ + effects into the engine (each capability degrades
  /// gracefully when unsupported).
  Future<void> _applyToEngine(AudioSettingsState settings) async {
    final Object? engine = _engineRef();
    if (engine is EqualizerControl && engine.equalizerAvailable) {
      final EqualizerInfo? info = await engine.queryEqualizer();
      if (info != null && info.bandCount > 0) {
        final List<double> gains = EqualizerGains.clampAll(
          EqualizerGains.resample(settings.eqGains, info.bandCount),
        );
        await engine.setEqualizerEnabled(enabled: settings.eqEnabled);
        for (var i = 0; i < gains.length; i++) {
          await engine.setEqualizerBandGain(i, gains[i]);
        }
      }
    }
    if (engine is AudioEffectsControl && engine.effectsAvailable) {
      await engine.applyEffects(settings.effects);
    }
  }

  /// Mutates the settings, persists the profile and re-applies.
  Future<void> _commit(AudioSettingsState next) async {
    final String? deviceKey = _deviceKey;
    if (deviceKey == null) {
      return;
    }
    state = state.copyWith(settings: next);
    await _applyToEngine(next);
    await _db.audioProfilesDao.upsert(
      deviceKey: deviceKey,
      outputDeviceId: state.outputDeviceId,
      label: state.outputDeviceLabel,
      values: AudioProfileCodec.toValues(next),
    );
  }

  // --- EQ -------------------------------------------------------------------

  Future<void> setEqEnabled(bool enabled) => _commit(
        state.settings.copyWith(eqEnabled: enabled),
      );

  Future<void> setEqGain(int band, double gainDb) {
    final List<double> gains = List<double>.of(state.settings.eqGains);
    while (gains.length < 5) {
      gains.add(0);
    }
    if (band < 0 || band >= gains.length) {
      return Future<void>.value();
    }
    gains[band] = EqualizerGains.clamp(gainDb);
    return _commit(
      state.settings.copyWith(eqGains: gains, eqPresetKey: ''),
    );
  }

  /// Applies a preset key (`builtin:Rock` or a user preset name) and
  /// persists the resulting gain vector.
  Future<List<double>?> applyEqPreset(
    String key,
    Future<List<double>?> resolveGains(String key),
  ) async {
    final List<double>? gains = await resolveGains(key);
    if (gains == null) {
      return null;
    }
    final List<double> normalized = List<double>.of(gains);
    while (normalized.length < 5) {
      normalized.add(0);
    }
    final AudioSettingsState next = state.settings.copyWith(
      eqGains: normalized.sublist(0, 5),
      eqPresetKey: key,
    );
    await _commit(next);
    return next.eqGains;
  }

  // --- Effects --------------------------------------------------------------

  Future<void> setBassBoost(int strength) => _commit(
        state.settings.copyWith(
          effects: state.settings.effects.copyWith(
            bassBoost: strength.clamp(0, 100),
          ),
        ),
      );

  Future<void> setVirtualizer(int strength) => _commit(
        state.settings.copyWith(
          effects: state.settings.effects.copyWith(
            virtualizer: strength.clamp(0, 100),
          ),
        ),
      );

  Future<void> setReverbPreset(String preset) => _commit(
        state.settings.copyWith(
          effects: state.settings.effects.copyWith(reverbPreset: preset),
        ),
      );

  Future<void> setBalance(double balance) => _commit(
        state.settings.copyWith(
          effects: state.settings.effects.copyWith(
            balance: balance.clamp(-1.0, 1.0).toDouble(),
          ),
        ),
      );

  Future<void> setForceMono(bool enabled) => _commit(
        state.settings.copyWith(
          effects: state.settings.effects.copyWith(forceMono: enabled),
        ),
      );

  // --- ReplayGain -----------------------------------------------------------

  Future<void> setReplayGainMode(ReplayGainMode mode) => _commit(
        state.settings.copyWith(replayGainMode: mode),
      );

  Future<void> setReplayGainPreamp(double preampDb) => _commit(
        state.settings.copyWith(
          replayGainPreampDb: preampDb.clamp(-6.0, 6.0).toDouble(),
        ),
      );

  // --- Transitions ----------------------------------------------------------

  Future<void> setCrossfadeSeconds(int seconds) => _commit(
        state.settings.copyWith(
          crossfadeSeconds:
              seconds.clamp(0, TransitionConfig.kMaxCrossfadeSeconds),
        ),
      );

  Future<void> setGapless(bool enabled) =>
      _commit(state.settings.copyWith(gapless: enabled));

  // --- Profiles -------------------------------------------------------------

  /// Every stored profile (profiles UI).
  Future<List<AudioProfileRow>> storedProfiles() {
    final String deviceKey = _deviceKey ?? '';
    return _db.audioProfilesDao.forDevice(deviceKey);
  }

  /// Resets the active profile to defaults.
  Future<void> resetProfile() => _commit(const AudioSettingsState());

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _deviceSub?.cancel();
    super.dispose();
  }
}

/// Manual provider: binds the DB, device key and the platform engine.
final audioEngineControllerProvider =
    StateNotifierProvider<AudioEngineController, AudioEngineState>(
  (ref) {
    final controller = AudioEngineController(
      db: ref.watch(databaseProvider),
      deviceKeyFuture: ref.watch(deviceIdProvider.future),
      engineRef: () => ref.read(playbackEngineProvider),
      outputDeviceTracker: const DefaultOutputDeviceTracker(),
    );
    unawaited(controller.init());
    return controller;
  },
);

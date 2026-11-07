import 'package:drift/drift.dart';

/// Per-output-device audio profile (Phase 8.4).
///
/// One row per `(deviceKey, outputDeviceId)`: the full sound setup
/// (EQ, effects, ReplayGain, transitions) remembered for a given output
/// (wired, BT phone, BT car…). `outputDeviceId` is a stable engine-level
/// key ('default' where the platform cannot report one).
@DataClassName('AudioProfileRow', companion: 'AudioProfilesCompanion')
@TableIndex(
  name: 'idx_audio_profiles_device_output',
  unique: true,
  columns: {#deviceKey, #outputDeviceId},
)
class AudioProfiles extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Stable per-install device id (same key as `eq_presets.deviceId`).
  TextColumn get deviceKey => text()();

  /// Output device identifier (engine-reported; 'default' fallback).
  TextColumn get outputDeviceId => text()();

  /// Human label (e.g. "Wired headphones") for the profiles UI.
  TextColumn get label => text().withDefault(const Constant(''))();

  /// Master EQ enable.
  BoolColumn get eqEnabled => boolean().withDefault(const Constant(true))();

  /// Per-band gains (dB), JSON array over the standard 5-band layout.
  TextColumn get eqGainsJson => text().withDefault(const Constant('[]'))();

  /// Active preset key (builtin:* or user name); empty = custom.
  TextColumn get eqPresetKey => text().withDefault(const Constant(''))();

  /// BassBoost strength 0..100.
  IntColumn get bassBoost => integer().withDefault(const Constant(0))();

  /// Virtualizer (surround) strength 0..100.
  IntColumn get virtualizer => integer().withDefault(const Constant(0))();

  /// Reverb preset name; empty = off.
  TextColumn get reverbPreset =>
      text().withDefault(const Constant(''))();

  /// Balance −1 (left) … +1 (right).
  RealColumn get balance => real().withDefault(const Constant(0.0))();

  /// Force mono downmix.
  BoolColumn get forceMono => boolean().withDefault(const Constant(false))();

  /// ReplayGain mode: off / track / album.
  TextColumn get replayGainMode =>
      text().withDefault(const Constant('off'))();

  /// ReplayGain pre-amp in dB (−6 … +6).
  RealColumn get replayGainPreampDb =>
      real().withDefault(const Constant(0.0))();

  /// Crossfade duration in seconds (0..30, 0 = off).
  IntColumn get crossfadeSeconds => integer().withDefault(const Constant(0))();

  /// Gapless playback preference.
  BoolColumn get gapless => boolean().withDefault(const Constant(true))();

  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
}

/// Equalizer orchestration (Stage 4, DAP feature 2.2): pushes gain
/// vectors into a capable engine and persists user presets per device in
/// the Drift `eq_presets` table.
///
/// The controller is engine-agnostic: an engine that implements
/// [EqualizerControl] gets the gains, every other engine degrades to
/// "preset management without live audio application" (still fully
/// testable and future-proof). All failures are non-throwing — a broken
/// EQ must never break playback.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/core/device/device_identity.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/eq_presets_dao.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/data/local/db/tables/eq_presets.dart';
import 'package:wavely/design_system/themes/theme_provider.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/equalizer/eq_presets.dart';
import 'package:wavely/playback/equalizer/equalizer_control.dart';

/// Preset lookup key prefix distinguishing built-in presets from rows in
/// `eq_presets`.
const String kBuiltinPresetPrefix = 'builtin:';

/// Facade over the engine EQ capability + per-device preset storage.
class EqualizerController {
  /// Creates the controller; [engine] may be `null` in tests that only
  /// exercise preset storage.
  EqualizerController({
    required AppDatabase db,
    required String deviceId,
    PlaybackEngine? engine,
  })  : _dao = db.eqPresetsDao,
        _deviceId = deviceId,
        _engine = engine;

  final EqPresetsDao _dao;
  final String _deviceId;
  final PlaybackEngine? _engine;

  /// The engine's EQ capability, or `null` when the engine is absent or
  /// does not implement [EqualizerControl].
  EqualizerControl? get engineEq {
    final PlaybackEngine? engine = _engine;
    if (engine is EqualizerControl) {
      return engine;
    }
    return null;
  }

  /// Whether gains can actually be applied to audio right now.
  Future<bool> get canApplyGains async {
    final EqualizerControl? eq = engineEq;
    if (eq == null || !eq.equalizerAvailable) {
      return false;
    }
    return (await eq.queryEqualizer()) != null;
  }

  /// Platform EQ facts (band count / range) or `null` when unavailable.
  Future<EqualizerInfo?> queryEngine() => engineEq?.queryEqualizer();

  /// Enables/disables the engine equalizer. `false` when no capable
  /// engine exists.
  Future<bool> setEnabled(bool enabled) async {
    final EqualizerControl? eq = engineEq;
    if (eq == null) {
      return false;
    }
    return eq.setEqualizerEnabled(enabled);
  }

  /// Clamps and applies [gainsDb] to the engine (resampling the standard
  /// layout to the engine's band count). Returns `true` when every band
  /// was accepted, `false` when no capable engine exists or the engine
  /// refused.
  Future<bool> applyGains(List<double> gainsDb) async {
    final EqualizerControl? eq = engineEq;
    if (eq == null || !eq.equalizerAvailable) {
      return false;
    }
    final EqualizerInfo? info = await eq.queryEqualizer();
    if (info == null || info.bandCount <= 0) {
      return false;
    }
    final List<double> gains = EqualizerGains.clampAll(gainsDb);
    final List<double> adapted =
        EqualizerGains.resample(gains, info.bandCount);
    var allApplied = true;
    for (var i = 0; i < adapted.length; i++) {
      // Out-of-range / refused bands degrade the result but never throw.
      final bool ok = await eq.setEqualizerBandGain(i, adapted[i]);
      if (!ok) {
        allApplied = false;
      }
    }
    return allApplied;
  }

  // --- Built-in presets -----------------------------------------------------

  /// The built-in preset catalogue.
  List<BuiltinEqPreset> get builtinPresets => kBuiltinEqPresets;

  /// Resolves a built-in preset by name (without the
  /// [kBuiltinPresetPrefix]).
  BuiltinEqPreset? builtinByName(String name) {
    for (final BuiltinEqPreset preset in kBuiltinEqPresets) {
      if (preset.name == name) {
        return preset;
      }
    }
    return null;
  }

  // --- User presets (Drift, per device) --------------------------------------

  /// User presets stored for this device.
  Future<List<EqPresetRow>> userPresets() => _dao.forDevice(_deviceId);

  /// Saves (or overwrites) a user preset for this device.
  Future<void> savePreset(String name, List<double> gainsDb) =>
      _dao.upsert(deviceId: _deviceId, name: name, gainsDb: gainsDb);

  /// Deletes a user preset; returns the removed row count.
  Future<int> deletePreset(String name) =>
      _dao.deleteByName(_deviceId, name);

  /// Applies a preset by key. Built-ins use the [kBuiltinPresetPrefix]
  /// (`builtin:Rock`), user presets are matched by plain name. Returns the
  /// applied gain vector, or `null` when the preset does not exist.
  Future<List<double>?> applyPreset(String key) async {
    final String name = key.startsWith(kBuiltinPresetPrefix)
        ? key.substring(kBuiltinPresetPrefix.length)
        : key;
    List<double>? gains;
    final BuiltinEqPreset? builtin = builtinByName(name);
    if (builtin != null) {
      gains = builtin.gainsDb;
    } else {
      final EqPresetRow? row = await _dao.byName(_deviceId, name);
      if (row != null) {
        gains = EqPresetRowCodec.decode(row);
      }
    }
    if (gains == null) {
      return null;
    }
    await applyGains(gains);
    return gains;
  }
}

/// Manual provider (playback layer keeps no codegen surface): binds the
/// controller to the app database, the stable device id and the platform
/// engine. All three defaults resolve through composition-root overrides,
/// so no `buildOverrides` change is required.
final equalizerControllerProvider = FutureProvider<EqualizerController>(
  (ref) async {
    return EqualizerController(
      db: ref.watch(databaseProvider),
      deviceId: await ref.watch(deviceIdProvider.future),
      engine: ref.watch(playbackEngineProvider),
    );
  },
);

/// Stable per-install device id over the app settings store (see
/// `DeviceIdentity`).
final deviceIdProvider = FutureProvider<String>((ref) async {
  return DeviceIdentity(store: ref.watch(settingsStoreProvider)).resolve();
});

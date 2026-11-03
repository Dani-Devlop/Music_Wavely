/// Stable per-install device identity used to scope per-device settings
/// (Stage 4: equalizer presets in `eq_presets`).
///
/// Wavely has no account-bound device registry (device_info_plus is only
/// used for the low-end performance heuristic), so a device here means
/// "one app installation": the first resolve generates a UUIDv4 and
/// persists it through the app-wide [SettingsStore]. Clearing app data
/// yields a new identity — acceptable for EQ presets and documented in
/// `docs/DAP_FEATURES.md`.
library;

import 'package:uuid/uuid.dart';
import 'package:wavely/core/settings/settings_store.dart';

/// Settings key holding the persisted device id.
const String kDeviceIdSettingsKey = 'wavely.device.id';

/// Resolves (and lazily creates) the stable device id over a
/// [SettingsStore].
class DeviceIdentity {
  /// Creates the resolver over [store]; [idGenerator] is injectable for
  /// deterministic tests.
  DeviceIdentity({required SettingsStore store, String Function()? idGenerator})
      : _store = store,
        _idGenerator = idGenerator;

  static const Uuid _uuid = Uuid();

  final SettingsStore _store;
  final String Function()? _idGenerator;

  String? _cached;

  /// Returns the persisted device id, creating + persisting a fresh UUIDv4
  /// when none exists yet. Store failures (read or write) degrade to a
  /// session-only id (stable for this process run) so callers never see a
  /// crash from a broken store.
  Future<String> resolve() async {
    final String? cached = _cached;
    if (cached != null) {
      return cached;
    }
    String? stored;
    try {
      stored = await _store.read<String>(kDeviceIdSettingsKey);
    } on Object {
      stored = null;
    }
    final String? trimmed = stored?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      _cached = trimmed;
      return trimmed;
    }
    final String generated = _idGenerator?.call() ?? _uuid.v4();
    try {
      await _store.write(kDeviceIdSettingsKey, generated);
    } on Object {
      // Session-only fallback (see doc).
    }
    _cached = generated;
    return generated;
  }
}

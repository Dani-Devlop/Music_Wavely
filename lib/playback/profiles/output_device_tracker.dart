/// Output-device identification (Phase 8.4).
///
/// Profiles are keyed by a stable output id. Platforms that can report the
/// real sink (wired / BT car / BT phone…) plug in here; the default
/// implementation reports a single `'default'` device with no change
/// events, which keeps every consumer simple and testable.
library;

import 'dart:async';

/// Contract for output-device tracking.
abstract interface class OutputDeviceTracker {
  /// Current output device id.
  Future<String> currentOutputDeviceId();

  /// Emits the new device id whenever the active output changes.
  Stream<String> get deviceChanges;

  /// Human label for a device id (profiles UI); falls back to the id.
  Future<String> deviceLabel(String deviceId) async => deviceId;
}

/// Default tracker: one static device, no change events.
class DefaultOutputDeviceTracker implements OutputDeviceTracker {
  const DefaultOutputDeviceTracker();

  @override
  Future<String> currentOutputDeviceId() async => kDefaultOutputDeviceId;

  @override
  Stream<String> get deviceChanges => const Stream<String>.empty();

  @override
  Future<String> deviceLabel(String deviceId) async => deviceId;
}

/// The fallback output key used when the platform cannot report a real
/// device.
const String kDefaultOutputDeviceId = 'default';

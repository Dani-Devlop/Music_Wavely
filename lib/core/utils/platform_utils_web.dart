import 'package:flutter/foundation.dart';

/// Web arm of the platform-utils conditional export declared in
/// `platform_utils.dart`.
///
/// `dart:io` is unavailable for browser builds (dart:io library docs,
/// Dart 3.9: "Browser-based apps can't use this library"), so this arm
/// mirrors the public surface of `platform_utils_io.dart` without it.
///
/// KEEP IN SYNC with `platform_utils_io.dart`: both arms must expose the
/// identical set of public symbols with identical semantics.

/// Heuristic thresholds for the low-end device heuristic below.
const int _lowRamThresholdMb = 3072;
const int _oldAndroidSdkInt = 29;
const int _defaultProcessorCount = 8;
const int _lowProcessorCount = 4;

/// Pluggable device-info resolver so tests can inject fake snapshots.
typedef DeviceInfoProvider = Future<DeviceInfoSnapshot?> Function();

/// Minimal device facts used for performance heuristics.
class DeviceInfoSnapshot {
  const DeviceInfoSnapshot({
    this.totalRamMb,
    this.androidSdkInt,
    this.processorCount,
  });

  final int? totalRamMb;
  final int? androidSdkInt;
  final int? processorCount;
}

/// Platform probing helpers that are safe to call from any widget or service.
abstract final class PlatformUtils {
  /// kIsWeb is always true on the web arm; kept for textual parity with the
  /// io arm.
  static bool get isWeb => kIsWeb;

  /// The web app is not a native mobile target.
  static bool get isMobile => false;

  /// The web app is not a native desktop target.
  static bool get isDesktop => false;

  static TargetPlatform get currentTargetPlatform => defaultTargetPlatform;
}

/// Pure heuristic over [DeviceInfoSnapshot]:
///
/// - low RAM: `totalRamMb < 3072`, or
/// - old Android with few cores: `androidSdkInt < 29` and
///   `processorCount <= 4` (defaulting to 8 cores when unknown).
///
/// Any provider failure resolves to `false` (never blocks playback features).
Future<bool> isLowEndDevice({DeviceInfoProvider? provider}) async {
  final effective = provider ?? defaultDeviceInfoProvider;
  try {
    final snapshot = await effective();
    if (snapshot == null) {
      return false;
    }
    final ramMb = snapshot.totalRamMb;
    final sdkInt = snapshot.androidSdkInt;
    final lowRam = ramMb != null && ramMb < _lowRamThresholdMb;
    final oldAndFewCores = sdkInt != null &&
        sdkInt < _oldAndroidSdkInt &&
        (snapshot.processorCount ?? _defaultProcessorCount) <=
            _lowProcessorCount;
    return lowRam || oldAndFewCores;
  } on Object catch (_) {
    return false;
  }
}

/// Web builds never report device facts: the io arm's documented contract is
/// "unsupported platforms (web, desktop) resolve to null", so the web arm
/// resolves to `null` unconditionally.
Future<DeviceInfoSnapshot?> defaultDeviceInfoProvider() async => null;

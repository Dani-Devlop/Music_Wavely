import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// IO (native mobile + desktop) arm of the platform-utils conditional
/// export declared in `platform_utils.dart`.
///
/// `dart:io` is unavailable for browser builds (dart:io library docs,
/// Dart 3.9: "Browser-based apps can't use this library"), so every symbol
/// that needs it lives here. Web builds resolve to `platform_utils_web.dart`
/// instead — the public surface (PlatformUtils, DeviceInfoSnapshot,
/// DeviceInfoProvider, isLowEndDevice, defaultDeviceInfoProvider) and its
/// semantics are identical on both arms.
///
/// KEEP IN SYNC with `platform_utils_web.dart`.

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
  static bool get isWeb => kIsWeb;

  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

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

/// Maps `device_info_plus` data to a [DeviceInfoSnapshot].
///
/// Notes on the pinned device_info_plus 13.x API:
/// - RAM is already reported in megabytes via `physicalRamSize`.
/// - There is no processor count field, so `Platform.numberOfProcessors` is
///   used instead.
/// - Unsupported platforms (web, desktop) resolve to `null`.
Future<DeviceInfoSnapshot?> defaultDeviceInfoProvider() async {
  try {
    if (kIsWeb) {
      return null;
    }
    if (Platform.isAndroid) {
      final android = await DeviceInfoPlugin().androidInfo;
      return DeviceInfoSnapshot(
        totalRamMb: android.physicalRamSize,
        androidSdkInt: android.version.sdkInt,
        processorCount: Platform.numberOfProcessors,
      );
    }
    if (Platform.isIOS) {
      final ios = await DeviceInfoPlugin().iosInfo;
      return DeviceInfoSnapshot(
        totalRamMb: ios.physicalRamSize,
        processorCount: Platform.numberOfProcessors,
      );
    }
    return null;
  } on Object catch (_) {
    return null;
  }
}

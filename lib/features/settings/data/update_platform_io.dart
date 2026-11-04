import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';

/// IO-platform asset suffix picker (Windows `.msix`, Linux `.AppImage`,
/// macOS `.dmg`, Android `.apk`). Selected by the conditional export in
/// `update_platform.dart`.
String defaultAssetSuffix() {
  if (Platform.isWindows) {
    return '.msix';
  }
  if (Platform.isLinux) {
    return '.appimage';
  }
  if (Platform.isMacOS) {
    return '.dmg';
  }
  if (Platform.isAndroid) {
    return '.apk';
  }
  return '';
}

/// Best-effort device ABI (Android only): the first installable ABI that
/// a released APK split covers, `null` off-Android or when the platform
/// lookup fails (tests, plugin load failure) — the caller then falls back
/// to the universal APK.
Future<String?> deviceAbi() async {
  if (!Platform.isAndroid) {
    return null;
  }
  try {
    final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
    const covered = <String>[
      'arm64-v8a',
      'armeabi-v7a',
      'x86_64',
    ];
    for (final abi in covered) {
      if (abis.contains(abi)) {
        return abi;
      }
    }
    return abis.isEmpty ? null : abis.first;
  } on Object {
    return null;
  }
}

/// True under `flutter test` (the harness sets `FLUTTER_TEST`): used to
/// keep network-touching convenience providers hermetic. Never true in a
/// real browser (web uses the stub variant).
bool get runningInFlutterTest =>
    Platform.environment.containsKey('FLUTTER_TEST');

import 'dart:io' show Platform;

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

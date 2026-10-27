/// Platform probing helpers shared by core, playback and UI layers.
///
/// Conditional export keeps `dart:io` out of web builds (dart:io library
/// docs, Dart 3.9: "Browser-based apps can't use this library"). The import
/// path and the public surface (PlatformUtils, DeviceInfoSnapshot,
/// DeviceInfoProvider, isLowEndDevice, defaultDeviceInfoProvider) are
/// identical on every platform:
///
/// - native (mobile + desktop): `platform_utils_io.dart`
/// - web: `platform_utils_web.dart`
///
/// The two arms must stay in sync — see the KEEP IN SYNC notes in each.
export 'package:wavely/core/utils/platform_utils_io.dart'
    if (dart.library.js_interop) 'package:wavely/core/utils/platform_utils_web.dart';

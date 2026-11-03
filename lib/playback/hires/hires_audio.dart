/// Hi-Res audio / bit-perfect playback support (Stage 4, DAP feature 2.1).
///
/// Two halves:
///
/// 1. **Desktop (media_kit/libmpv)** — bit-perfect output via
///    `DesktopPlaybackEngine.setExclusiveMode` (mpv `audio-exclusive`);
///    Wavely never forces `audio-samplerate` / `audio-format`, so the
///    decoder's native sample rate / bit depth is passed through whenever
///    the output device supports it. See `docs/HIRES_AUDIO.md`.
///
/// 2. **Android** — exclusive AAudio output on Android 14+ (API 34) is
///    requested through the `app.wavely.hires.audio` platform channel
///    (method `requestExclusiveMode`). The native side is NOT committed
///    (the repo scaffolds its Android runner in CI); until the owner adds
///    the Kotlin handler the channel throws `MissingPluginException`, which
///    this controller converts into a clean `granted: false` — playback is
///    never blocked. The exact Kotlin implementation sketch lives in
///    `docs/HIRES_AUDIO.md`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wavely/core/utils/platform_utils.dart';

/// The platform channel that carries the exclusive-mode request.
@visibleForTesting
const MethodChannel kHiResAudioChannel = MethodChannel('app.wavely.hires.audio');

/// Result of a hi-res / exclusive-mode request.
class HiResRequestResult {
  /// Creates the result.
  const HiResRequestResult({required this.granted, required this.reason});

  /// Whether the platform granted (or is expected to grant) the request.
  final bool granted;

  /// Human-readable explanation (surfaced in logs / diagnostics).
  final String reason;
}

/// Pure policy helpers (unit-tested without any platform dependency).
abstract final class HiResAudioPolicy {
  /// Android 14 (U) — the first release where AAudio exposes
  /// `AAudioStream_requestMode`/`PERFORMANCE_MODE_EXCLUSIVE` behaviour
  /// reliably enough for a "bit-perfect" promise.
  static const int androidExclusiveMinSdk = 34;

  /// Whether an Android device with API level [sdkInt] qualifies for the
  /// exclusive-mode request (`null` = unknown platform → not supported).
  static bool androidExclusiveSupported(int? sdkInt) =>
      sdkInt != null && sdkInt >= androidExclusiveMinSdk;
}

/// Activates the platform exclusive mode (injectable for tests).
typedef ExclusiveModeActivator = Future<bool> Function();

/// Reports the current Android API level, or `null` off-Android
/// (injectable for tests).
typedef AndroidSdkIntProvider = Future<int?> Function();

/// Orchestrates the Android 14+ exclusive-mode request.
class HiResAudioController {
  /// Creates the controller; both hooks default to the real bindings and
  /// are injectable so tests run without a platform.
  HiResAudioController({
    ExclusiveModeActivator? activator,
    AndroidSdkIntProvider? sdkIntProvider,
  })  : _activator = activator ?? defaultRequestAndroidExclusiveMode,
        _sdkIntProvider = sdkIntProvider ?? defaultAndroidSdkIntProvider;

  final ExclusiveModeActivator _activator;
  final AndroidSdkIntProvider _sdkIntProvider;

  /// Runs the full Android policy: gate on API level, then request the
  /// channel. Failures degrade to `granted: false` with a reason.
  Future<HiResRequestResult> enableAndroidExclusiveMode() async {
    final int? sdk = await _sdkIntProvider();
    if (!HiResAudioPolicy.androidExclusiveSupported(sdk)) {
      return HiResRequestResult(
        granted: false,
        reason:
            'Android API ${sdk ?? 'unknown'} < '
            '${HiResAudioPolicy.androidExclusiveMinSdk} — AAudio exclusive '
            'mode unsupported',
      );
    }
    try {
      final bool granted = await _activator();
      return HiResRequestResult(
        granted: granted,
        reason: granted
            ? 'AAudio exclusive mode granted (API $sdk)'
            : 'Platform channel refused exclusive mode (API $sdk)',
      );
    } on Object catch (e) {
      return HiResRequestResult(
        granted: false,
        reason: 'Exclusive-mode request failed: $e',
      );
    }
  }
}

/// Default [AndroidSdkIntProvider]: reuses the shared device-info snapshot
/// (web resolves to `null`, matching `DeviceInfoSnapshot.androidSdkInt`
/// semantics).
Future<int?> defaultAndroidSdkIntProvider() async {
  if (PlatformUtils.isWeb || !PlatformUtils.isMobile) {
    return null;
  }
  try {
    final snapshot = await defaultDeviceInfoProvider();
    return snapshot?.androidSdkInt;
  } on Object {
    return null;
  }
}

/// Default [ExclusiveModeActivator]: invokes the `app.wavely.hires.audio`
/// channel. A missing native handler (the current state — the Android
/// runner is scaffolded in CI) or a platform error resolves to `false`,
/// never throws.
Future<bool> defaultRequestAndroidExclusiveMode() async {
  if (PlatformUtils.isWeb || !PlatformUtils.isAndroid) {
    return false;
  }
  try {
    final Object? response =
        await kHiResAudioChannel.invokeMethod<Object?>('requestExclusiveMode');
    return response is bool && response;
  } on MissingPluginException {
    // Native handler not implemented yet — documented stub state.
    return false;
  } on PlatformException {
    return false;
  }
}

/// IO/test probe: never iOS, never standalone (there is no navigator).
/// Selected by the conditional export in `ios_guidance_banner.dart`.
class IosPlatformProbe {
  const IosPlatformProbe();

  /// True when running on iPhone/iPad Safari.
  bool get isIos => false;

  /// True when installed as a standalone PWA (`navigator.standalone`).
  bool get isStandalone => false;
}

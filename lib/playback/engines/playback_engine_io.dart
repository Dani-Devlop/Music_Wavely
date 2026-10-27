import 'package:wavely/core/utils/platform_utils.dart';
import 'package:wavely/playback/engines/desktop_playback_engine.dart';
import 'package:wavely/playback/engines/mobile_playback_engine.dart';
import 'package:wavely/playback/engines/playback_engine.dart';

/// IO-platform engine factory: media_kit on desktop, just_audio on mobile.
///
/// Both engine classes live in separate files; the unused one is expected to
/// be tree-shaken per release target.
PlaybackEngine createEngine() {
  if (PlatformUtils.isDesktop) {
    return DesktopPlaybackEngine();
  }
  return MobilePlaybackEngine();
}

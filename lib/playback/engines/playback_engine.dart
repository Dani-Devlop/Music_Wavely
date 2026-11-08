import 'package:wavely/domain/entities/entities.dart';

/// Lifecycle of the playback engine.
enum PlaybackState { stopped, loading, buffering, playing, paused, completed, error }

/// Repeat behaviour of the playback queue.
enum RepeatMode { off, all, one }

/// Transport-agnostic playback contract.
///
/// Implementations wrap just_audio / media_kit per platform; UI and queue
/// code depend only on this interface.
abstract class PlaybackEngine {
  Future<void> load(Track t, {Duration? startAt});

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration p);

  Stream<Duration> get positionStream;

  Stream<PlaybackState> get stateStream;

  Future<void> setQueue(List<Track> tracks, {int startIndex = 0});

  /// Adjusts the output volume — 0.0 is silent, 1.0 is full scale.
  ///
  /// Stage 3 final polish (BUG-9): used by the parental censor-fallback
  /// policy (`mute` decision). The base implementation is a no-op so test
  /// fakes and minimal engines stay source-compatible; platform engines
  /// override it.
  Future<void> setVolume(double volume) async {}

  /// Registers transport callbacks that system surfaces (lock screen
  /// media controls, headset buttons, the quick-settings tile) drive.
  ///
  /// Phase 9: the queue layer (QueueManager) owns next/previous semantics,
  /// so it registers itself here; engines forward the callbacks into their
  /// audio_service handler / media session. The base implementation is a
  /// no-op so test fakes and minimal engines stay source-compatible.
  void setTransportCallbacks({
    void Function()? onNext,
    void Function()? onPrevious,
    void Function()? onTogglePlayPause,
  }) {}

  /// Seeks relative to the current position (headset long-press FF/RW,
  /// lock-screen press-and-hold seek). Negative offsets clamp at zero.
  /// The base implementation is a no-op; platform engines override it.
  Future<void> seekBy(Duration offset) async {}

  /// Publishes the current track's lyrics to the media session (lock
  /// screen / Android Auto can surface them when supported). Passing null
  /// clears. Base no-op — platform engines override it.
  Future<void> setLyrics(String? lyrics) async {}

  Future<void> dispose();
}

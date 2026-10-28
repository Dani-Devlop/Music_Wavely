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

  Future<void> dispose();
}

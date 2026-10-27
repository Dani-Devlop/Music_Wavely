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

  Future<void> dispose();
}

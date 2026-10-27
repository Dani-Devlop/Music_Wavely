import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

/// [TrackLauncher] adapter that hands track lists to [QueueManager].
///
/// Composition-root binding for library/search tiles: replaces the queue,
/// starts at [playTracks]' [startIndex] and plays immediately. The play is
/// optimistic ([QueueManager.play] flips the state first); the engine state
/// stream reconciles afterwards.
class QueueTrackLauncher implements TrackLauncher {
  /// Creates the launcher over [manager].
  const QueueTrackLauncher(this._manager);

  final QueueManager _manager;

  @override
  Future<void> playTracks(List<Track> tracks, {int startIndex = 0}) async {
    await _manager.setQueue(tracks, startIndex: startIndex);
    await _manager.play();
  }
}

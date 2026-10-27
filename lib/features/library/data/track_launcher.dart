import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/domain/entities/entities.dart';

/// Hands a list of tracks to the playback layer as a queue.
///
/// The library feature never imports playback internals; Task 4's
/// composition root overrides [trackLauncherProvider] with an adapter onto
/// the queue manager.
abstract class TrackLauncher {
  /// Starts playback of [tracks] beginning at [startIndex] (default 0).
  ///
  /// The abstract member carries the `= 0` default so callers may omit it
  /// (play-all buttons) and implementations keep a matching default.
  Future<void> playTracks(List<Track> tracks, {int startIndex = 0});
}

/// Playback bridge consumed by library/search tiles. Throws until Task 4
/// overrides it in the composition root (all library screens are unusable
/// before that anyway).
final trackLauncherProvider = Provider<TrackLauncher>(
  (ref) => throw UnimplementedError(
    'trackLauncherProvider must be overridden in the composition root (Task 4)',
  ),
);

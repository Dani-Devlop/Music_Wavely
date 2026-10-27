import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

/// Bottom-of-app mini player bound to the queue state.
///
/// Renders nothing (collapses to zero height) while the queue is empty and
/// slides in with the standard motion token once a track exists. Router
/// wiring stays out of this file: callers pass [onOpenNowPlaying] (Task 4
/// pushes ['/now-playing']).
class MiniPlayerHost extends ConsumerWidget {
  const MiniPlayerHost({required this.onOpenNowPlaying, super.key});

  final VoidCallback onOpenNowPlaying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(queueManagerProvider.notifier);
    final queue = ref.watch(queueManagerProvider);
    final track = queue.currentTrack;
    final child = track == null
        ? const SizedBox(
            width: double.infinity,
            key: ValueKey<String>('mini-player-empty'),
          )
        : MiniPlayer(
            key: const ValueKey<String>('mini-player'),
            track: track,
            isPlaying: queue.playbackState == PlaybackState.playing,
            position: queue.position,
            duration: Duration(milliseconds: track.durationMs),
            onPlayPause: () => unawaited(manager.togglePlayPause()),
            onTap: onOpenNowPlaying,
            onNext: () => unawaited(manager.next()),
          );
    return AnimatedSwitcher(
      duration: WavelyDurations.normal,
      curve: WavelyDurations.standard,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(animation);
        return SlideTransition(position: slide, child: child);
      },
      child: child,
    );
  }
}

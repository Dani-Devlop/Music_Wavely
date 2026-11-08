import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavely/features/player/presentation/mini_player_host.dart';
import 'package:wavely/features/player/presentation/now_playing_screen.dart';
import 'package:wavely/features/player/presentation/queue_sheet.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

part 'mini_player_widget.g.dart';

/// Phase 10.2: whether the mini player is hidden (swipe-down dismiss).
/// Ephemeral UI state — it resets to visible whenever the queue goes empty
/// so the bar reappears with the next track.
@Riverpod(keepAlive: true)
class MiniPlayerHidden extends _$MiniPlayerHidden {
  @override
  bool build() => false;

  void setHidden(bool hidden) => state = hidden;
}

/// App-shell wrapper around [MiniPlayerHost] with the router wiring the
/// host deliberately avoids, plus the Phase 10.2 gesture set:
///
/// - swipe **up** expands the now-playing screen,
/// - swipe **down** dismisses the bar (resets on the next queue change),
/// - swipe **right / left** jumps to the next / previous track,
/// - double-tap on the cover toggles play/pause (wired through
///   [MiniPlayerHost] → MiniPlayer),
/// - long-press opens the queue sheet (existing behaviour).
class MiniPlayerWidget extends ConsumerWidget {
  /// Creates the shell mini player.
  const MiniPlayerWidget({super.key});

  /// Horizontal velocity above which a drag counts as a track change.
  static const double _swipeVelocityThreshold = 500;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(miniPlayerHiddenProvider);
    return GestureDetector(
      onVerticalDragEnd: (details) =>
          _onVerticalDragEnd(context, ref, details),
      onHorizontalDragEnd: (details) =>
          _onHorizontalDragEnd(context, ref, details),
      onLongPress: () => unawaited(_showQueueSheet(context)),
      // Swipe gestures only make sense with a track on screen.
      child: Semantics(
        hint: 'Open queue',
        child: hidden
            ? const SizedBox(width: double.infinity, height: 0)
            : MiniPlayerHost(
                onOpenNowPlaying: () =>
                    unawaited(context.push(NowPlayingScreen.route)),
              ),
      ),
    );
  }

  void _onVerticalDragEnd(
    BuildContext context,
    WidgetRef ref,
    DragEndDetails details,
  ) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (velocity < -_swipeVelocityThreshold) {
      // Swipe up → expand the now-playing screen.
      unawaited(context.push(NowPlayingScreen.route));
    } else if (velocity > _swipeVelocityThreshold) {
      // Swipe down → dismiss the bar.
      ref.read(miniPlayerHiddenProvider.notifier).setHidden(true);
    }
  }

  void _onHorizontalDragEnd(
    BuildContext context,
    WidgetRef ref,
    DragEndDetails details,
  ) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    final queue = ref.read(queueManagerProvider.notifier);
    if (velocity > _swipeVelocityThreshold) {
      // Swipe right → next track (Musicolet direction parity).
      unawaited(queue.next());
    } else if (velocity < -_swipeVelocityThreshold) {
      // Swipe left → previous track.
      unawaited(queue.previous());
    }
  }

  Future<void> _showQueueSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => QueueSheet(
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    );
  }
}

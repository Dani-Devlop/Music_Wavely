import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wavely/features/player/presentation/mini_player_host.dart';
import 'package:wavely/features/player/presentation/now_playing_screen.dart';
import 'package:wavely/features/player/presentation/queue_sheet.dart';

/// App-shell wrapper around [MiniPlayerHost] with the router wiring the host
/// deliberately avoids: tap opens now-playing, long-press opens the queue
/// sheet (hint 'Open queue').
class MiniPlayerWidget extends ConsumerWidget {
  /// Creates the shell mini player.
  const MiniPlayerWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      hint: 'Open queue',
      child: GestureDetector(
        onLongPress: () => unawaited(_showQueueSheet(context)),
        child: MiniPlayerHost(
          onOpenNowPlaying: () =>
              unawaited(context.push(NowPlayingScreen.route)),
        ),
      ),
    );
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

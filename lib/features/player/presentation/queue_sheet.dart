import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/core/extensions/extensions.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

/// Bottom-sheet content listing the queue with drag-to-reorder and
/// swipe-to-remove.
///
/// Designed to be hosted inside `showModalBottomSheet` by the caller
/// (app shell / now playing entry point, Task 4 wiring):
///
/// ```dart
/// showModalBottomSheet(context, builder: (_) => QueueSheet(onClose: () => Navigator.pop(context)));
/// ```
class QueueSheet extends ConsumerWidget {
  const QueueSheet({required this.onClose, super.key});

  /// Invoked by the close button; typically pops the hosting route.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(queueManagerProvider.notifier);
    final queue = ref.watch(queueManagerProvider);
    final colors = context.wavelyColors;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.lg,
            Spacing.sm,
            Spacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text('Up next', style: WavelyTypography.title20()),
              ),
              IconButton(
                tooltip: 'Close queue',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        if (queue.tracks.isEmpty)
          const Expanded(
            child: EmptyState(
              icon: Icons.queue_music_outlined,
              title: 'Queue is empty',
            ),
          )
        else
          Expanded(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: Spacing.lg),
              itemCount: queue.tracks.length,
              onReorder: (oldIndex, newIndex) =>
                  unawaited(manager.reorderQueue(oldIndex, newIndex)),
              itemBuilder: (context, index) => _buildRow(
                context,
                colors,
                manager,
                queue,
                index,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRow(
    BuildContext context,
    WavelySemanticColors colors,
    QueueManager manager,
    QueueState queue,
    int index,
  ) {
    final track = queue.tracks[index];
    final isCurrent = index == queue.currentIndex;
    // STABLE per-track key: ReorderableListView tracks the dragged item by
    // key across rebuilds — embedding the index here (`id#$index`) made the
    // key change the moment the item moved, corrupting the drop target.
    final rowKey = ValueKey<String>(
      '${track.id ?? track.sourceTrackId}',
    );
    return Material(
      key: rowKey,
      color: Colors.transparent,
      child: Dismissible(
        key: rowKey,
        direction: DismissDirection.endToStart,
        background: Container(
          color: colors.error,
          alignment: AlignmentDirectional.centerEnd,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        onDismissed: (_) => unawaited(manager.removeFromQueue(index)),
        child: ListTile(
          leading: isCurrent
              ? Icon(Icons.graphic_eq, color: colors.accentColors.accent)
              : Text(
                  '${index + 1}',
                  style: WavelyTypography.body14Medium(
                    color: colors.textTertiary,
                  ),
                ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WavelyTypography.body14Medium(
              color: isCurrent
                  ? colors.accentColors.accent
                  : colors.textPrimary,
            ),
          ),
          subtitle: Text(
            track.artistOrUnknown,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WavelyTypography.caption12(color: colors.textSecondary),
          ),
          trailing: Text(
            track.displayDuration,
            style: WavelyTypography.body14(color: colors.textSecondary),
          ),
          onTap: () =>
              unawaited(manager.setQueue(queue.tracks, startIndex: index)),
        ),
      ),
    );
  }
}

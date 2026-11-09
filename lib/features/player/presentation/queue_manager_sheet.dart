/// The Musicolet-parity Queue Manager (v1.0.2 Android UI).
///
/// Matches the owner-specified screenshot semantics:
/// - a live list of the queue entries with **drag handles** to reorder,
/// - per-row **edit** (jump to song info / rename note) and **delete**
///   icons,
/// - named queue slots (like Musicolet's "A", "Download", …) the current
///   playing queue can be snapshot into and restored from,
/// - the big green **REMOVE ALL OTHER QUEUES** button pinned at the
///   bottom.
///
/// Queue snapshots live in presentation-layer storage (shared_preferences
/// as JSON track-id lists resolved through the queue's own track source),
/// so the playback engine and database are untouched.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/player/presentation/musicolet_palette.dart';
import 'package:wavely/features/player/presentation/song_options_sheet.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

/// SharedPreferences key holding the named-queue registry JSON:
/// `[{"name":"A","ids":[1,2,3]},…]`.
const String kNamedQueuesPrefsKey = 'wavely.namedQueues.v1';

class _NamedQueue {
  const _NamedQueue({required this.name, required this.ids});

  final String name;
  final List<int> ids;

  Map<String, Object> toJson() => <String, Object>{
        'name': name,
        'ids': ids,
      };

  static _NamedQueue fromJson(Map<String, Object?> json) => _NamedQueue(
        name: json['name'] as String? ?? '',
        ids: <int>[
          for (final id in (json['ids'] as List<Object?>? ?? <Object?>[]))
            if (id is int) id,
        ],
      );
}

Future<List<_NamedQueue>> _loadQueues() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kNamedQueuesPrefsKey);
  if (raw == null || raw.isEmpty) {
    return <_NamedQueue>[];
  }
  try {
    final list = (jsonDecode(raw) as List<Object?>)
        .whereType<Map<String, Object?>>()
        .map(_NamedQueue.fromJson)
        .toList(growable: false);
    return list;
  } on Object {
    return <_NamedQueue>[];
  }
}

Future<void> _saveQueues(List<_NamedQueue> queues) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    kNamedQueuesPrefsKey,
    jsonEncode(<Object>[for (final q in queues) q.toJson()]),
  );
}

/// Opens the Musicolet queue-manager sheet.
Future<void> showQueueManagerSheet(BuildContext context) {
  return showMusicoletSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => const _QueueManagerSheet(),
  );
}

class _QueueManagerSheet extends ConsumerStatefulWidget {
  const _QueueManagerSheet();

  @override
  ConsumerState<_QueueManagerSheet> createState() =>
      _QueueManagerSheetState();
}

class _QueueManagerSheetState extends ConsumerState<_QueueManagerSheet> {
  List<_NamedQueue> _queues = <_NamedQueue>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final queues = await _loadQueues();
    if (!mounted) {
      return;
    }
    setState(() {
      _queues = queues;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(queueManagerProvider);
    final manager = ref.read(queueManagerProvider.notifier);
    final height = MediaQuery.sizeOf(context).height * 0.85;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: <Widget>[
            // -- header -------------------------------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.lg, Spacing.md, Spacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.queue_music_rounded,
                      color: MusicoletColors.green),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Text(
                      'Queue manager',
                      style: WavelyTypography.title18(
                        color: MusicoletColors.text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Save current queue',
                    icon: const Icon(Icons.save_outlined,
                        color: MusicoletColors.green),
                    onPressed: _saveCurrentAsQueue,
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close,
                        color: MusicoletColors.textDim),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: MusicoletColors.divider),
            // -- body ---------------------------------------------------
            Expanded(
              child: _loaded
                  ? ListView(
                      padding: const EdgeInsets.only(bottom: Spacing.md),
                      children: <Widget>[
                        _SectionLabel('Now playing'),
                        if (queue.tracks.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(Spacing.lg),
                            child: Text(
                              'The queue is empty.',
                              style: TextStyle(
                                color: MusicoletColors.textDim,
                              ),
                            ),
                          )
                        else
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            padding: EdgeInsets.zero,
                            itemCount: queue.tracks.length,
                            onReorder: (oldIndex, newIndex) => unawaited(
                              manager.reorderQueue(oldIndex, newIndex),
                            ),
                            itemBuilder: (context, index) =>
                                _QueueTrackRow(
                              key: ValueKey<String>(
                                'qm-track-${queue.tracks[index].id ?? queue.tracks[index].sourceTrackId}',
                              ),
                              index: index,
                              track: queue.tracks[index],
                              isCurrent: index == queue.currentIndex,
                              onRemove: () => unawaited(
                                manager.removeFromQueue(index),
                              ),
                              onInfo: () {
                                Navigator.of(context).pop();
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) {
                                    if (mounted) {
                                      unawaited(
                                        showSongOptionsSheet(
                                          context,
                                          ref,
                                          queue.tracks[index],
                                        ),
                                      );
                                    }
                                  },
                                );
                              },
                              onReorder: () {},
                            ),
                          ),
                        _SectionLabel('Saved queues'),
                        if (_queues.isEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(
                              Spacing.lg, Spacing.xs, Spacing.lg, 0,
                            ),
                            child: Text(
                              'No saved queues yet — use the save icon to '
                              'snapshot the current queue.',
                              style: TextStyle(
                                color: MusicoletColors.textDim,
                              ),
                            ),
                          )
                        else
                          for (var i = 0; i < _queues.length; i++)
                            _NamedQueueRow(
                              key: ValueKey<String>('qm-queue-$i'),
                              name: _queues[i].name,
                              count: _queues[i].ids.length,
                              onApply: () => _applyQueue(i),
                              onRename: () => _renameQueue(i),
                              onDelete: () => _deleteQueue(i),
                            ),
                      ],
                    )
                  : const Center(
                      child: CircularProgressIndicator(
                        color: MusicoletColors.green,
                      ),
                    ),
            ),
            // -- green action bar ---------------------------------------
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg,
              ),
              decoration: const BoxDecoration(
                color: MusicoletColors.sheet,
                border: Border(
                  top: BorderSide(color: MusicoletColors.divider),
                ),
              ),
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  key: const Key('queue-manager-remove-all'),
                  style: FilledButton.styleFrom(
                    backgroundColor: MusicoletColors.green,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed:
                      _queues.isEmpty ? null : _removeAllOtherQueues,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text(
                    'REMOVE ALL OTHER QUEUES',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- actions ---------------------------------------------------------------

  Future<void> _saveCurrentAsQueue() async {
    final queue = ref.read(queueManagerProvider);
    if (queue.tracks.isEmpty) {
      return;
    }
    final defaultName = String.fromCharCode(65 + _queues.length); // A, B, C…
    final name = await _promptName('Save queue', initial: defaultName);
    if (name == null || name.isEmpty || !mounted) {
      return;
    }
    final ids = <int>[
      for (final track in queue.tracks)
        if (track.id case final id?) id,
    ];
    setState(() {
      _queues = <_NamedQueue>[
        ..._queues,
        _NamedQueue(name: name, ids: ids),
      ];
    });
    await _saveQueues(_queues);
  }

  Future<void> _applyQueue(int index) async {
    final target = _queues[index];
    final source = ref.read(queueTrackSourceProvider);
    final tracks = await source.byIds(target.ids);
    if (tracks.isEmpty || !mounted) {
      return;
    }
    await ref
        .read(queueManagerProvider.notifier)
        .setQueue(List<Track>.of(tracks));
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _renameQueue(int index) async {
    final name = await _promptName(
      'Rename queue',
      initial: _queues[index].name,
    );
    if (name == null || name.isEmpty || !mounted) {
      return;
    }
    setState(() {
      _queues[index] = _NamedQueue(name: name, ids: _queues[index].ids);
    });
    await _saveQueues(_queues);
  }

  Future<void> _deleteQueue(int index) async {
    setState(() {
      _queues = <_NamedQueue>[
        for (var i = 0; i < _queues.length; i++)
          if (i != index) _queues[i],
      ];
    });
    await _saveQueues(_queues);
  }

  Future<void> _removeAllOtherQueues() async {
    setState(() {
      _queues = <_NamedQueue>[];
    });
    await _saveQueues(_queues);
  }

  Future<String?> _promptName(String title, {String? initial}) {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: MusicoletColors.sheet,
        title: Text(
          title,
          style: WavelyTypography.title18(color: MusicoletColors.text),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: WavelyTypography.body14(color: MusicoletColors.text),
          decoration: const InputDecoration(
            labelText: 'Queue name',
            labelStyle: TextStyle(color: MusicoletColors.textDim),
          ),
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MusicoletColors.green,
              foregroundColor: Colors.black,
            ),
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// -- rows ---------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.md, Spacing.lg, Spacing.xs,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(
              color: MusicoletColors.green,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
      );
}

class _QueueTrackRow extends StatelessWidget {
  const _QueueTrackRow({
    required this.index,
    required this.track,
    required this.isCurrent,
    required this.onRemove,
    required this.onInfo,
    required this.onReorder,
    super.key,
  });

  final int index;
  final Track track;
  final bool isCurrent;
  final VoidCallback onRemove;
  final VoidCallback onInfo;
  final VoidCallback onReorder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
      child: Row(
        children: <Widget>[
          // Drag handle (Musicolet parity).
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.drag_handle_rounded,
                  size: 20, color: MusicoletColors.textDim),
            ),
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WavelyTypography.body14Medium(
                          color: isCurrent
                              ? MusicoletColors.green
                              : MusicoletColors.text,
                        ),
                      ),
                      Text(
                        '${track.artistOrUnknown} · ${track.displayDuration}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WavelyTypography.caption12(
                          color: MusicoletColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Song options',
                  icon: const Icon(Icons.more_vert_rounded,
                      size: 20, color: MusicoletColors.textDim),
                  onPressed: onInfo,
                ),
                IconButton(
                  tooltip: 'Remove from queue',
                  icon: const Icon(Icons.close_rounded,
                      size: 20, color: MusicoletColors.textDim),
                  onPressed: onRemove,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NamedQueueRow extends StatelessWidget {
  const _NamedQueueRow({
    required this.name,
    required this.count,
    required this.onApply,
    required this.onRename,
    required this.onDelete,
    super.key,
  });

  final String name;
  final int count;
  final VoidCallback onApply;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
      child: ListTile(
        dense: true,
        leading: const Icon(
          Icons.queue_rounded,
          color: MusicoletColors.green,
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: WavelyTypography.body14Medium(color: MusicoletColors.text),
        ),
        subtitle: Text(
          '$count songs',
          style: WavelyTypography.caption12(color: MusicoletColors.textDim),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: 'Rename',
              icon: const Icon(Icons.edit_outlined,
                  size: 20, color: MusicoletColors.textDim),
              onPressed: onRename,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: MusicoletColors.textDim),
              onPressed: onDelete,
            ),
          ],
        ),
        onTap: onApply,
      ),
    );
  }
}

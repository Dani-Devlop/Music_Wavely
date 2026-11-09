import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/audio_cutter/presentation/audio_cutter_screen.dart';
import 'package:wavely/features/library/data/file_operations/file_operations.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/features/library/presentation/file_ops_dialogs.dart';
import 'package:wavely/features/library/presentation/playlist_picker.dart';
import 'package:wavely/features/tag_editor/presentation/tag_editor_screen.dart';

import 'package:wavely/data/local/db/database_provider.dart';

/// Immutable multi-selection snapshot scoped to one list.
class SelectionState {
  const SelectionState({
    this.selectedIds = const <String>{},
    this.selectionMode = false,
  });

  /// The current selection (stable track keys), in selection order.
  final Set<String> selectedIds;

  /// True while the selection mode is active (long-press entered).
  final bool selectionMode;

  /// Copy with fields replaced.
  SelectionState copyWith({Set<String>? selectedIds, bool? selectionMode}) =>
      SelectionState(
        selectedIds: selectedIds ?? this.selectedIds,
        selectionMode: selectionMode ?? this.selectionMode,
      );
}

/// Drives the multi-selection of one list (Phase 6): long-press enters the
/// mode, taps toggle rows, Select All / Invert / Clear mutate in bulk.
class SelectionController extends StateNotifier<SelectionState> {
  SelectionController() : super(const SelectionState());

  /// Enters selection mode selecting [id] (long-press entry point).
  void startSelection(String id) {
    state = SelectionState(
      selectedIds: <String>{id},
      selectionMode: true,
    );
  }

  /// v1.0.2: enters selection mode WITHOUT pre-selecting a row. Since the
  /// long-press now opens the Musicolet 14-option context sheet, the
  /// multi-select mode is entered from the dedicated toggle button next to
  /// the quick-search box; rows are then tapped to select them.
  void enterSelectionMode() {
    state = state.copyWith(selectionMode: true);
  }

  /// Leaves selection mode and clears the selection.
  void exitSelectionMode() {
    state = const SelectionState();
  }

  /// Toggles [id]; tapping the last selected row exits selection mode.
  void toggle(String id) {
    if (!state.selectionMode) {
      startSelection(id);
      return;
    }
    final next = {...state.selectedIds};
    if (!next.remove(id)) {
      next.add(id);
    }
    state = SelectionState(
      selectedIds: next,
      selectionMode: next.isNotEmpty,
    );
  }

  /// Selects every id in [ids].
  void selectAll(Iterable<String> ids) {
    state = state.copyWith(
      selectedIds: {...ids},
      selectionMode: true,
    );
  }

  /// Flips the selection over the full [allIds] universe.
  void invert(Iterable<String> allIds) {
    final next = <String>{
      for (final id in allIds)
        if (!state.selectedIds.contains(id)) id,
    };
    state = SelectionState(
      selectedIds: next,
      selectionMode: next.isNotEmpty,
    );
  }

  /// Exits selection mode.
  void clear() => state = const SelectionState();
}

/// Selection scopes are per list (tab id or detail screen id) so two lists
/// never share selection state.
final selectionControllerProvider =
    StateNotifierProvider.autoDispose
        .family<SelectionController, SelectionState, String>(
  (ref, scope) => SelectionController(),
);

/// Bulk actions for the multi-select bar (Play / Play Next / Add to Queue /
/// Add to Playlist / Delete / Share). All failures degrade to a snackbar so
/// one bad row never wedges the UI.
abstract final class LibrarySelectionActions {
  /// Starts playback of the selected rows in their list order.
  static Future<void> play(
    WidgetRef ref,
    List<Track> selectedTracks,
  ) async {
    if (selectedTracks.isEmpty) {
      return;
    }
    await ref.read(trackLauncherProvider).playTracks(selectedTracks);
  }

  /// Inserts the selected rows after the current track.
  static Future<void> playNext(
    WidgetRef ref,
    List<Track> selectedTracks,
  ) async {
    if (selectedTracks.isEmpty) {
      return;
    }
    await ref.read(queueBridgeProvider).playNext(selectedTracks);
  }

  /// Appends the selected rows to the queue.
  static Future<void> addToQueue(
    WidgetRef ref,
    List<Track> selectedTracks,
  ) async {
    if (selectedTracks.isEmpty) {
      return;
    }
    await ref.read(queueBridgeProvider).appendToQueue(selectedTracks);
  }

  /// Opens the playlist picker, then adds the selected rows to the chosen
  /// (or newly created) playlist. Returns the chosen name, or null when the
  /// picker was dismissed.
  static Future<String?> addToPlaylist(
    BuildContext context,
    WidgetRef ref,
    List<Track> selectedTracks,
  ) async {
    if (selectedTracks.isEmpty || !context.mounted) {
      return null;
    }
    final name = await showPlaylistPicker(context, ref);
    if (name == null || !context.mounted) {
      return null;
    }
    final dao = ref.read(databaseProvider).playlistsDao;
    final playlists = await dao.getAll();
    Playlist? match;
    for (final playlist in playlists) {
      if (playlist.name.toLowerCase() == name.toLowerCase()) {
        match = playlist;
        break;
      }
    }
    final playlistId =
        match?.id ?? await dao.createPlaylist(name);
    final ids = <int>[
      for (final track in selectedTracks)
        if (track.id case final id?) id,
    ];
    await dao.addTracks(playlistId, ids);
    return name;
  }

  /// Confirms, then removes the selected rows from the library database
  /// (audio files stay on disk). Playlists cascade via foreign keys.
  static Future<bool> delete(
    BuildContext context,
    WidgetRef ref,
    List<Track> selectedTracks,
  ) async {
    final ids = <int>[
      for (final track in selectedTracks)
        if (track.id case final id?) id,
    ];
    if (ids.isEmpty || !context.mounted) {
      return false;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from library?'),
        content: Text(
          '$ids ${ids.length == 1 ? 'track' : 'tracks'} will be removed '
          'from the Wavely library. The audio files stay on disk.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return false;
    }
    await ref.read(databaseProvider).tracksDao.deleteByIds(ids);
    return true;
  }

  /// Shares the selected rows as a text list (title — artist). Uses the OS
  /// share sheet via `share_plus`; degrades to the clipboard when no share
  /// target accepts the payload.
  static Future<void> share(BuildContext context, List<Track> tracks) async {
    if (tracks.isEmpty) {
      return;
    }
    final text = <String>[
      for (final track in tracks) '${track.title} — ${track.artistOrUnknown}',
    ].join('\n');
    try {
      await SharePlus.instance.share(
        ShareParams(text: 'Shared from Wavely:\n$text'),
      );
    } on Object catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copied to clipboard')),
        );
      }
    }
  }

  /// Opens the tag editor for the selected rows' files (batch mode when
  /// more than one local track is selected).
  static Future<void> editTags(
    BuildContext context,
    List<Track> selectedTracks,
  ) async {
    final List<String> paths = <String>[
      for (final Track track in selectedTracks)
        if (track.filePath case final String path? when path.isNotEmpty) path,
    ];
    if (paths.isEmpty || !context.mounted) {
      announce(context, 'Selected tracks have no local files');
      return;
    }
    await GoRouter.of(context).push(kTagEditorRoute, extra: paths);
  }

  /// Opens the audio cutter for a single selected track.
  static Future<void> cutAudio(
    BuildContext context,
    List<Track> selectedTracks,
  ) async {
    if (selectedTracks.length != 1) {
      announce(context, 'Select exactly one track to cut');
      return;
    }
    final String? path = selectedTracks.first.filePath;
    if (path == null || path.isEmpty) {
      announce(context, 'Selected track has no local file');
      return;
    }
    await GoRouter.of(context).push(kAudioCutterRoute, extra: path);
  }

  /// Opens the file-operations flow (rename / move / copy / delete with
  /// confirmation dialogs) over the selected rows' local files.
  static Future<void> fileOperations(
    BuildContext context,
    WidgetRef ref,
    List<Track> selectedTracks,
  ) async {
    final List<String> paths = <String>[
      for (final Track track in selectedTracks)
        if (track.filePath case final String path? when path.isNotEmpty) path,
    ];
    if (paths.isEmpty || !context.mounted) {
      announce(context, 'Selected tracks have no local files');
      return;
    }
    final FileOpBatchResult? result =
        await showFileOpsSheet(context, ref, paths);
    if (result == null || !context.mounted) {
      return;
    }
    final int ok = result.succeeded.length;
    final int failed = result.failed.length;
    announce(
      context,
      failed == 0
          ? 'Done: $ok ${ok == 1 ? 'file' : 'files'} updated'
          : 'Done with errors: $ok ok, $failed failed',
    );
  }

  /// Convenience snackbar used by the selection bar after each action.
  static void announce(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Top bar shown while a selection is active: count, Select All / Invert and
/// the action row (Play, Play Next, Add to Queue, Add to Playlist, Delete,
/// Share).
class SelectionBar extends ConsumerWidget {
  /// Creates the selection bar for [scope]; [allIds] is the unfiltered id
  /// universe of the list and [tracksOf] resolves ids back to tracks.
  const SelectionBar({
    required this.scope,
    required this.allIds,
    required this.tracksOf,
    super.key,
  });

  final String scope;
  final Set<String> allIds;
  final Track? Function(String id) tracksOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final selection = ref.watch(selectionControllerProvider(scope));
    final controller = ref.read(selectionControllerProvider(scope).notifier);
    final selectedTracks = <Track>[
      for (final id in selection.selectedIds)
        if (tracksOf(id) case final track?) track,
    ];

    Future<void> runAction(Future<void> Function() action) async {
      try {
        await action();
      } on Object catch (error) {
        if (context.mounted) {
          LibrarySelectionActions.announce(
            context,
            'Action failed: $error',
          );
        }
      }
    }

    return Container(
      key: const ValueKey<String>('selection-bar'),
      color: colors.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  key: const ValueKey<String>('selection-close'),
                  icon: Icon(Icons.close, color: colors.textSecondary),
                  tooltip: 'Exit selection',
                  onPressed: controller.clear,
                ),
                Expanded(
                  child: Text(
                    '${selectedTracks.length} selected',
                    key: const ValueKey<String>('selection-count'),
                    style: WavelyTypography.body14Medium(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey<String>('selection-select-all'),
                  onPressed: () => controller.selectAll(allIds),
                  child: const Text('Select All'),
                ),
                TextButton(
                  key: const ValueKey<String>('selection-invert'),
                  onPressed: () => controller.invert(allIds),
                  child: const Text('Invert'),
                ),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  _ActionChip(
                    icon: Icons.play_arrow_rounded,
                    label: 'Play',
                    enabled: selectedTracks.isNotEmpty,
                    onTap: () => runAction(
                      () async {
                        await LibrarySelectionActions.play(
                          ref,
                          selectedTracks,
                        );
                        controller.clear();
                        if (context.mounted) {
                          LibrarySelectionActions.announce(
                            context,
                            'Playing ${selectedTracks.length} '
                            '${selectedTracks.length == 1 ? 'track' : 'tracks'}',
                          );
                        }
                      },
                    ),
                  ),
                  _ActionChip(
                    icon: Icons.queue_rounded,
                    label: 'Play Next',
                    enabled: selectedTracks.isNotEmpty,
                    onTap: () => runAction(() async {
                      await LibrarySelectionActions.playNext(
                        ref,
                        selectedTracks,
                      );
                      controller.clear();
                      if (context.mounted) {
                        LibrarySelectionActions.announce(
                          context,
                          'Queued to play next',
                        );
                      }
                    }),
                  ),
                  _ActionChip(
                    icon: Icons.playlist_add,
                    label: 'Add to Queue',
                    enabled: selectedTracks.isNotEmpty,
                    onTap: () => runAction(() async {
                      await LibrarySelectionActions.addToQueue(
                        ref,
                        selectedTracks,
                      );
                      controller.clear();
                      if (context.mounted) {
                        LibrarySelectionActions.announce(
                          context,
                          'Added to queue',
                        );
                      }
                    }),
                  ),
                  _ActionChip(
                    icon: Icons.playlist_add_check,
                    label: 'Add to Playlist',
                    enabled: selectedTracks.isNotEmpty,
                    onTap: () => runAction(() async {
                      final name =
                          await LibrarySelectionActions.addToPlaylist(
                        context,
                        ref,
                        selectedTracks,
                      );
                      if (context.mounted && name != null) {
                        LibrarySelectionActions.announce(
                          context,
                          'Added to "$name"',
                        );
                      }
                    }),
                  ),
                  _ActionChip(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    enabled: selectedTracks.isNotEmpty,
                    danger: true,
                    onTap: () => runAction(() async {
                      final removed = await LibrarySelectionActions.delete(
                        context,
                        ref,
                        selectedTracks,
                      );
                      if (removed) {
                        controller.clear();
                        if (context.mounted) {
                          LibrarySelectionActions.announce(
                            context,
                            'Removed from library',
                          );
                        }
                      }
                    }),
                  ),
                  _ActionChip(
                    icon: Icons.share_outlined,
                    label: 'Share',
                    enabled: selectedTracks.isNotEmpty,
                    onTap: () => runAction(() async {
                      await LibrarySelectionActions.share(
                        context,
                        selectedTracks,
                      );
                    }),
                  ),
                  _ActionChip(
                    key: const ValueKey<String>('selection-edit-tags'),
                    icon: Icons.edit_outlined,
                    label: 'Edit Tags',
                    enabled: selectedTracks.isNotEmpty,
                    onTap: () => runAction(() async {
                      await LibrarySelectionActions.editTags(
                        context,
                        selectedTracks,
                      );
                    }),
                  ),
                  _ActionChip(
                    key: const ValueKey<String>('selection-cut-audio'),
                    icon: Icons.content_cut_rounded,
                    label: 'Cut',
                    enabled: selectedTracks.length == 1,
                    onTap: () => runAction(() async {
                      await LibrarySelectionActions.cutAudio(
                        context,
                        selectedTracks,
                      );
                    }),
                  ),
                  _ActionChip(
                    key: const ValueKey<String>('selection-file-ops'),
                    icon: Icons.folder_open_rounded,
                    label: 'File ops',
                    enabled: selectedTracks.isNotEmpty,
                    onTap: () => runAction(() async {
                      await LibrarySelectionActions.fileOperations(
                        context,
                        ref,
                        selectedTracks,
                      );
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.enabled,
    this.danger = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final color = !enabled
        ? colors.textTertiary
        : danger
            ? colors.error
            : colors.accentColors.accent;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: Spacing.sm),
      child: InkWell(
        borderRadius: AppRadii.bMd,
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: color),
              const SizedBox(width: Spacing.xs),
              Text(
                label,
                style: WavelyTypography.caption12(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

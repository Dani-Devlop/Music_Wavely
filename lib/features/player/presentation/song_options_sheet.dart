/// The Musicolet-parity 14-option song context menu (v1.0.2 Android UI).
///
/// Long-pressing any song opens this dark charcoal bottom sheet with the
/// EXACT option list from the owner spec (in Musicolet's order):
///
/// 1. Bookmarks/Notes   8.  Audio cutter
/// 2. A-B repeat        9.  Set as ringtone
/// 3. Play speed/pitch  10. Share song
/// 4. Add to a queue    11. Delete permanently
/// 5. Add to playlists  12. Show/hide/customize
/// 6. Edit tags         13. Quick access shortcuts
/// 7. Move to folder    14. Song info
///
/// Every row is wired to a REAL shipped capability. Rows whose backend
/// capability does not exist yet (A-B repeat, ringtone, show/hide,
/// shortcuts) render disabled with an honest subtitle — never a fake
/// action.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/audio_cutter/presentation/audio_cutter_screen.dart';
import 'package:wavely/features/library/presentation/file_ops_dialogs.dart';
import 'package:wavely/features/library/presentation/selection_controller.dart';
import 'package:wavely/features/player/presentation/musicolet_palette.dart';
import 'package:wavely/features/tag_editor/presentation/tag_editor_screen.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

/// shared_preferences key prefix for per-track bookmarks/notes
/// (presentation-layer storage; the key includes the stable track key so
/// local and remote tracks never collide).
const String kTrackNoteKeyPrefix = 'wavely.trackNotes.';

/// Stable per-track key for notes.
String trackNoteKey(int? id, String sourceTrackId) =>
    '$kTrackNoteKeyPrefix${id ?? sourceTrackId}';

/// Opens the 14-option Musicolet context sheet for [track].
Future<void> showSongOptionsSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
) {
  return showMusicoletSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _SongOptionsSheet(track: track),
  );
}

class _SongOptionsSheet extends ConsumerStatefulWidget {
  const _SongOptionsSheet({required this.track});

  final Track track;

  @override
  ConsumerState<_SongOptionsSheet> createState() => _SongOptionsSheetState();
}

class _SongOptionsSheetState extends ConsumerState<_SongOptionsSheet> {
  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final canFileOps = track.filePath != null && track.filePath!.isNotEmpty;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _SheetHeader(track: track),
            const Divider(height: 1, color: MusicoletColors.divider),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _Option(
                      icon: Icons.bookmark_border_rounded,
                      label: 'Bookmarks/Notes',
                      onTap: () => _popThen(_editNote),
                    ),
                    _Option(
                      icon: Icons.repeat_on_outlined,
                      label: 'A-B repeat',
                      enabled: false,
                      subtitle: 'Loop selection — coming with the '
                          'engine loop API',
                    ),
                    _Option(
                      icon: Icons.speed_rounded,
                      label: 'Play speed and pitch',
                      onTap: () => _popThen(_editSpeed),
                    ),
                    _Option(
                      icon: Icons.queue_rounded,
                      label: 'Add to a queue',
                      onTap: () => _popThen(_addToQueue),
                    ),
                    _Option(
                      icon: Icons.playlist_add_rounded,
                      label: 'Add to playlists',
                      onTap: () => _popThen(_addToPlaylist),
                    ),
                    _Option(
                      icon: Icons.edit_outlined,
                      label: 'Edit tags',
                      enabled: canFileOps,
                      subtitle:
                          canFileOps ? null : 'Only available for local files',
                      onTap: () => _popThen(_openTagEditor),
                    ),
                    _Option(
                      icon: Icons.drive_file_move_outline,
                      label: 'Move to folder',
                      enabled: canFileOps,
                      subtitle:
                          canFileOps ? null : 'Only available for local files',
                      onTap: () => _popThen(() => _fileOp()),
                    ),
                    _Option(
                      icon: Icons.content_cut_rounded,
                      label: 'Audio cutter',
                      enabled: canFileOps,
                      subtitle:
                          canFileOps ? null : 'Only available for local files',
                      onTap: () => _popThen(_openCutter),
                    ),
                    _Option(
                      icon: Icons.notifications_active_outlined,
                      label: 'Set as ringtone',
                      enabled: false,
                      subtitle: 'Needs the ringtone platform channel',
                    ),
                    _Option(
                      icon: Icons.ios_share_rounded,
                      label: 'Share song',
                      enabled: canFileOps,
                      subtitle:
                          canFileOps ? null : 'Only available for local files',
                      onTap: () => _popThen(_share),
                    ),
                    _Option(
                      icon: Icons.delete_forever_outlined,
                      label: 'Delete permanently',
                      enabled: canFileOps,
                      subtitle:
                          canFileOps ? null : 'Only available for local files',
                      danger: true,
                      onTap: () => _popThen(_fileOp),
                    ),
                    _Option(
                      icon: Icons.visibility_outlined,
                      label: 'Show/hide/customize',
                      enabled: false,
                      subtitle: 'Library visibility rules — coming soon',
                    ),
                    _Option(
                      icon: Icons.shortcut_rounded,
                      label: 'Quick access shortcuts',
                      enabled: false,
                      subtitle: 'Home-screen shortcuts — coming soon',
                    ),
                    _Option(
                      icon: Icons.info_outline_rounded,
                      label: 'Song info',
                      onTap: () => _popThen(
                        () => unawaited(
                          showTrackInfoDialog(context, widget.track),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _popThen(VoidCallback action) {
    Navigator.of(context).pop();
    // Let the sheet dismiss before opening the next surface (avoids
    // nested route conflicts under go_router).
    WidgetsBinding.instance.addPostFrameCallback((_) => action());
  }

  // -- real actions ---------------------------------------------------------

  Future<void> _addToQueue() async {
    final manager = ref.read(queueManagerProvider.notifier);
    await manager.appendToQueue(<Track>[widget.track]);
    _toast('Added to the queue');
  }

  Future<void> _addToPlaylist() async {
    await LibrarySelectionActions.addToPlaylist(
      context,
      ref,
      <Track>[widget.track],
    );
  }

  Future<void> _openTagEditor() async {
    if (!mounted) {
      return;
    }
    await context.push(
      kTagEditorRoute,
      extra: <String>[widget.track.filePath!],
    );
  }

  Future<void> _openCutter() async {
    if (!mounted) {
      return;
    }
    await context.push(kAudioCutterRoute, extra: widget.track.filePath);
  }

  Future<void> _fileOp() async {
    if (!mounted) {
      return;
    }
    // showFileOpsSheet runs its own confirmation dialog for move/delete.
    await showFileOpsSheet(context, ref, <String>[widget.track.filePath!]);
  }

  Future<void> _share() async {
    final path = widget.track.filePath;
    if (path == null || !mounted) {
      return;
    }
    final text =
        '${widget.track.title} — ${widget.track.artistOrUnknown}';
    try {
      await SharePlus.instance.share(
        ShareParams(files: <XFile>[XFile(path)], text: text),
      );
    } on Object catch (_) {
      // No share target accepted the file — degrade to a text share.
      if (!mounted) {
        return;
      }
      await SharePlus.instance.share(ShareParams(text: text));
    }
  }

  Future<void> _editNote() async {
    final key = trackNoteKey(widget.track.id, widget.track.sourceTrackId);
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(key) ?? '';
    if (!mounted) {
      return;
    }
    final controller = TextEditingController(text: existing);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: MusicoletColors.sheet,
        title: Text(
          'Bookmarks/Notes',
          style: WavelyTypography.title18(color: MusicoletColors.text),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          style: WavelyTypography.body14(color: MusicoletColors.text),
          decoration: const InputDecoration(
            hintText: 'Note for this song…',
            hintStyle: TextStyle(color: MusicoletColors.textDim),
          ),
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
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) {
                await prefs.remove(key);
              } else {
                await prefs.setString(key, text);
              }
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _editSpeed() {
    final manager = ref.read(queueManagerProvider.notifier);
    final queue = ref.read(queueManagerProvider);
    unawaited(
      showMusicoletSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const _SheetTitle('Play speed and pitch'),
              Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: <Widget>[
                    for (final speed in const <double>[
                      0.5, 0.75, 1.0, 1.25, 1.5, 2.0,
                    ])
                      ChoiceChip(
                        label: Text('${speed}x'),
                        selected: (queue.speed - speed).abs() < 0.001,
                        selectedColor: MusicoletColors.green,
                        labelStyle: WavelyTypography.body14Medium(
                          color: (queue.speed - speed).abs() < 0.001
                              ? Colors.black
                              : MusicoletColors.text,
                        ),
                        onSelected: (_) {
                          manager.setSpeed(speed);
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  Spacing.lg, 0, Spacing.lg, Spacing.lg,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'Pitch shifting arrives with the engine rate/pitch '
                    'API.',
                    style: TextStyle(color: MusicoletColors.textDim),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: MusicoletColors.greenDark,
        content: Text(
          message,
          style: WavelyTypography.body14(color: Colors.white),
        ),
      ),
    );
  }
}

// -- shared sheet chrome ----------------------------------------------------

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg, Spacing.lg, Spacing.lg, Spacing.md,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 44,
            height: 44,
            child: WavelyCover(label: track.title, coverPath: track.coverPath),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WavelyTypography.title18(color: MusicoletColors.text),
                ),
                Text(
                  track.artistOrUnknown,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WavelyTypography.caption12(
                    color: MusicoletColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            text,
            style: WavelyTypography.title18(color: MusicoletColors.text),
          ),
        ),
      );
}

/// One compact Musicolet menu row (green-tinted icon + label).
class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.enabled = true,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool enabled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? MusicoletColors.textDim
        : danger
            ? const Color(0xFFEF5350)
            : MusicoletColors.green;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg, vertical: Spacing.sm + 2,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 22, color: color),
            const SizedBox(width: Spacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WavelyTypography.body14Medium(
                      color: enabled
                          ? MusicoletColors.text
                          : MusicoletColors.textDim,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WavelyTypography.micro10(
                        color: MusicoletColors.textDim,
                      ),
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

/// Musicolet "Song info" dialog (shared by the context sheet and the
/// now-playing Info icon).
Future<void> showTrackInfoDialog(BuildContext context, Track track) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: MusicoletColors.sheet,
      title: Text(
        'Song info',
        style: WavelyTypography.title18(color: MusicoletColors.text),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _infoRow('Title', track.title),
          _infoRow('Artist', track.artistOrUnknown),
          if (track.album?.isNotEmpty == true)
            _infoRow('Album', track.album!),
          if (track.genre?.isNotEmpty == true)
            _infoRow('Genre', track.genre!),
          _infoRow('Duration', track.displayDuration),
          _infoRow('Format', track.format.toUpperCase()),
          if (track.bitrate != null)
            _infoRow('Bitrate', '${track.bitrate} kbps'),
          if (track.filePath?.isNotEmpty == true)
            _infoRow('Path', track.filePath!),
        ],
      ),
      actions: <Widget>[
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: MusicoletColors.green,
            foregroundColor: Colors.black,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Widget _infoRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: WavelyTypography.caption12(
                color: MusicoletColors.textDim,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WavelyTypography.body14(color: MusicoletColors.text),
            ),
          ),
        ],
      ),
    );

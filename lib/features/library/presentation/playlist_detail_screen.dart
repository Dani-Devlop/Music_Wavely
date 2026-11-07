import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';

/// Detail screen for one playlist: track list in persisted order, play-all,
/// remove-track and rename.
class PlaylistDetailScreen extends ConsumerStatefulWidget {
  /// Creates the detail screen for [playlistId].
  const PlaylistDetailScreen({
    required this.playlistId,
    required this.playlistName,
    super.key,
  });

  final int playlistId;
  final String playlistName;

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final tracksAsync = ref.watch(playlistTracksProvider(widget.playlistId));

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          widget.playlistName,
          style: WavelyTypography.title20(color: colors.textPrimary),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename playlist',
            onPressed: () => unawaited(_rename()),
          ),
        ],
      ),
      body: tracksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorState(
          message: 'Could not load the playlist',
          detail: error.toString(),
          onRetry: () =>
              ref.invalidate(playlistTracksProvider(widget.playlistId)),
        ),
        data: (tracks) {
          if (tracks.isEmpty) {
            return const EmptyState(
              icon: Icons.playlist_add,
              title: 'Empty playlist',
              subtitle:
                  'Select tracks in any library list and choose '
                  '"Add to Playlist".',
            );
          }
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Row(
                  children: <Widget>[
                    FilledButton.icon(
                      key: const ValueKey<String>('play-playlist-button'),
                      onPressed: () => unawaited(
                        ref
                            .read(trackLauncherProvider)
                            .playTracks(List<Track>.of(tracks)),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        'Play all (${tracks.length})',
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: Spacing.lg),
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return TrackTile(
                      key: ValueKey<String>(
                          'playlist-track-${track.id ?? index}'),
                      track: track,
                      trailing: IconButton(
                        icon: Icon(Icons.remove_circle_outline,
                            color: colors.textTertiary),
                        tooltip: 'Remove from playlist',
                        onPressed: () => unawaited(_removeTrack(track)),
                      ),
                      onTap: () => unawaited(
                        ref
                            .read(trackLauncherProvider)
                            .playTracks(
                              List<Track>.of(tracks),
                              startIndex: index,
                            ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: widget.playlistName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) {
      return;
    }
    await ref
        .read(databaseProvider)
        .playlistsDao
        .renamePlaylist(widget.playlistId, name);
    ref.invalidate(playlistsProvider);
    ref.invalidate(playlistTracksProvider(widget.playlistId));
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _removeTrack(Track track) async {
    if (track.id == null) {
      return;
    }
    await ref
        .read(databaseProvider)
        .playlistsDao
        .removeTrack(widget.playlistId, track.id!);
    ref.invalidate(playlistsProvider);
    ref.invalidate(playlistTracksProvider(widget.playlistId));
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';
import 'package:wavely/features/library/presentation/playlist_detail_screen.dart';
import 'package:wavely/features/library/presentation/quick_search_box.dart';

/// Playlists tab (Phase 6): every user playlist with item counts, create /
/// rename / delete, quick search and sort memory (name or newest).
class PlaylistsTab extends ConsumerStatefulWidget {
  /// Creates the playlists tab.
  const PlaylistsTab({super.key});

  @override
  ConsumerState<PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends ConsumerState<PlaylistsTab> {
  String _query = '';
  bool _nameAscending = true;

  Future<void> _createPlaylist() async {
    final name = await _promptName(
      title: 'New playlist',
      hint: 'Playlist name',
    );
    if (name == null || name.isEmpty) {
      return;
    }
    await ref.read(databaseProvider).playlistsDao.createPlaylist(name);
    ref.invalidate(playlistsProvider);
  }

  Future<String?> _promptName({
    required String title,
    required String hint,
    String? initial,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const ValueKey<String>('playlist-dialog-name'),
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final playlistsAsync = ref.watch(playlistsProvider);

    return Column(
      children: <Widget>[
        Expanded(
          child: playlistsAsync.when(
            loading: () => ListView.builder(
              padding: const EdgeInsets.all(Spacing.lg),
              itemCount: 4,
              itemBuilder: (context, index) => const Padding(
                padding: EdgeInsets.only(bottom: Spacing.sm),
                child: ShimmerBox(height: 64),
              ),
            ),
            error: (error, stackTrace) => ErrorState(
              message: 'Could not load playlists',
              detail: error.toString(),
              onRetry: () => ref.invalidate(playlistsProvider),
            ),
            data: (playlists) {
              var visible = <_PlaylistRow>[
                for (final playlist in playlists)
                  if (quickSearchMatches(playlist.name, _query))
                    _PlaylistRow(
                      id: playlist.id,
                      name: playlist.name,
                      itemCount: playlist.itemCount,
                      createdAt: playlist.createdAt,
                    ),
              ];
              visible.sort((a, b) {
                final cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
                return _nameAscending ? cmp : -cmp;
              });
              if (playlists.isEmpty) {
                return EmptyState(
                  icon: Icons.playlist_add,
                  title: 'No playlists yet',
                  subtitle: 'Group your tracks into playlists.',
                  ctaLabel: 'Create playlist',
                  onCta: () => unawaited(_createPlaylist()),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(Spacing.lg),
                children: <Widget>[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const ValueKey<String>('create-playlist-button'),
                      onPressed: () => unawaited(_createPlaylist()),
                      icon: const Icon(Icons.add),
                      label: const Text('Create playlist'),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  for (final row in visible)
                    ListTile(
                      key: ValueKey<String>('playlist-${row.id}'),
                      leading: Icon(
                        Icons.playlist_play_rounded,
                        color: colors.accentColors.accent,
                      ),
                      title: Text(
                        row.name,
                        style: WavelyTypography.body14Medium(
                          color: colors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        '${row.itemCount} '
                        '${row.itemCount == 1 ? 'track' : 'tracks'}',
                        style: WavelyTypography.caption12(
                          color: colors.textTertiary,
                        ),
                      ),
                      trailing: row.id == null
                          ? null
                          : IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: colors.textTertiary),
                              tooltip: 'Delete playlist',
                              onPressed: () => unawaited(_deletePlaylist(row)),
                            ),
                      onTap: () {
                        if (row.id != null) {
                          unawaited(
                            Navigator.push<void>(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => PlaylistDetailScreen(
                                  playlistId: row.id!,
                                  playlistName: row.name,
                                ),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  if (visible.isEmpty && _query.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.all(Spacing.lg),
                      child: Text('No playlists match your filter.'),
                    ),
                ],
              );
            },
          ),
        ),
        QuickSearchBox(
          filterKey: const ValueKey<String>('quick-search-playlists'),
          hintText: 'Filter Playlists…',
          onQueryChanged: (query) => setState(() => _query = query),
        ),
      ],
    );
  }

  Future<void> _deletePlaylist(_PlaylistRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text('"${row.name}" and its tracks membership will be '
            'removed. The tracks stay in your library.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || row.id == null) {
      return;
    }
    await ref.read(databaseProvider).playlistsDao.deletePlaylist(row.id!);
    ref.invalidate(playlistsProvider);
  }
}

class _PlaylistRow {
  const _PlaylistRow({
    required this.id,
    required this.name,
    required this.itemCount,
    required this.createdAt,
  });

  final int? id;
  final String name;
  final int itemCount;
  final DateTime createdAt;
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/design_system.dart';

/// Bottom sheet that picks (or creates) a playlist for the multi-select
/// "Add to Playlist" action. Returns the chosen/created playlist name, or
/// null when dismissed.
Future<String?> showPlaylistPicker(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => const _PlaylistPickerSheet(),
  );
}

class _PlaylistPickerSheet extends ConsumerStatefulWidget {
  const _PlaylistPickerSheet();

  @override
  ConsumerState<_PlaylistPickerSheet> createState() =>
      _PlaylistPickerSheetState();
}

class _PlaylistPickerSheetState extends ConsumerState<_PlaylistPickerSheet> {
  List<(int id, String name)>? _playlists;
  bool _creating = false;
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final playlists = await ref.read(databaseProvider).playlistsDao.getAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _playlists = <(int, String)>[
        for (final playlist in playlists)
          if (playlist.id case final id?) (id, playlist.name),
      ];
    });
  }

  Future<void> _createAndReturn() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      return;
    }
    final id = await ref.read(databaseProvider).playlistsDao.createPlaylist(name);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop((id, name).$2);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: Spacing.lg,
          right: Spacing.lg,
          top: Spacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Add to playlist',
              style: WavelyTypography.title20(color: colors.textPrimary),
            ),
            const SizedBox(height: Spacing.md),
            if (_playlists == null)
              const Center(child: CircularProgressIndicator())
            else ...<Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _playlists!.length,
                  itemBuilder: (context, index) {
                    final (id, name) = _playlists![index];
                    return ListTile(
                      key: ValueKey<String>('playlist-pick-$id'),
                      leading: Icon(Icons.queue_music_rounded,
                          color: colors.accentColors.accent),
                      title: Text(
                        name,
                        style: WavelyTypography.body14Medium(
                          color: colors.textPrimary,
                        ),
                      ),
                      onTap: () => Navigator.of(context).pop(name),
                    );
                  },
                ),
              ),
              if (_playlists!.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                  child: Text(
                    'No playlists yet — create one below.',
                    style: WavelyTypography.caption12(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: Spacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('playlist-name-field'),
                    controller: _nameController,
                    style: WavelyTypography.body14(color: colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'New playlist name',
                      hintStyle:
                          WavelyTypography.caption12(color: colors.textTertiary),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _creating ? _createAndReturn() : null,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                IconButton.filled(
                  key: const ValueKey<String>('playlist-create-button'),
                  onPressed:
                      _nameController.text.trim().isEmpty ? null : _createAndReturn,
                  icon: const Icon(Icons.check),
                  tooltip: 'Create playlist',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

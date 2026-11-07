import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/library_view_config.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';
import 'package:wavely/features/library/presentation/quick_search_box.dart';
import 'package:wavely/features/library/presentation/sort_menu.dart';

/// Pure folder-tree helpers built from the distinct indexed file paths.
abstract final class FolderTree {
  /// Immediate child folders of [current] ('' = root view). Returns
  /// (name, path, direct track count) triples; [paths] are the distinct
  /// indexed file paths (original separators preserved).
  static List<({String name, String path, int trackCount})> childFolders(
    List<String> paths,
    String current,
  ) {
    final children = <String, int>{};
    final prefix = current.isEmpty
        ? ''
        : LibraryVisibility.normalizePrefix(current);
    for (final path in paths) {
      if (!path.startsWith(prefix)) {
        continue;
      }
      final rest = path.substring(prefix.length);
      if (rest.isEmpty) {
        continue;
      }
      final separator = RegExp(r'[/\\]');
      final match = separator.firstMatch(rest);
      if (match == null) {
        // Direct file of the current folder — not part of a child folder.
        continue;
      }
      final name = rest.substring(0, match.start);
      if (name.isEmpty) {
        continue;
      }
      final childPath = '$prefix$name';
      children.update(childPath, (count) => count, ifAbsent: () => 0);
      // Direct file (no deeper folder part) counts for this child.
      if (!separator.hasMatch(rest.substring(match.start + 1))) {
        children[childPath] = children[childPath]! + 1;
      }
    }
    final names = children.keys.toList()..sort();
    return <({String name, String path, int trackCount})>[
      for (final childPath in names)
        (
          name: childPath.split(RegExp(r'[/\\]')).last,
          path: childPath,
          trackCount: children[childPath] ?? 0,
        ),
    ];
  }

  /// Breadcrumb segments of [folder] (for the back navigation).
  static List<String> crumbs(String folder) {
    if (folder.isEmpty) {
      return const <String>[];
    }
    return folder.split(RegExp(r'[/\\]'))..removeWhere((s) => s.isEmpty);
  }

  /// Parent path of [folder] ('' for top-level folders).
  static String parentOf(String folder) {
    final crumbs = FolderTree.crumbs(folder);
    if (crumbs.length <= 1) {
      return '';
    }
    final separator =
        folder.contains('\\') && !folder.contains('/') ? '\\' : '/';
    return folder.substring(
      0,
      folder.length - (crumbs.last.length + separator.length),
    );
  }
}

/// Folder browser (Phase 6): two view types — a simple folder tree and the
/// library view (tracks of the current folder) — plus the persisted folder
/// blacklist/whitelist and the "ignore tracks shorter than N seconds"
/// filter.
class FolderBrowserScreen extends ConsumerStatefulWidget {
  /// Creates the folder browser; [initialFolder] may be empty for the root
  /// view and [initialMode] picks the persisted default view type.
  const FolderBrowserScreen({
    this.initialFolder = '',
    this.initialMode = FolderBrowserMode.tree,
    super.key,
  });

  final String initialFolder;
  final FolderBrowserMode initialMode;

  /// Pushes the browser and returns once it is popped.
  static Future<void> open(
    BuildContext context, {
    String folder = '',
    FolderBrowserMode mode = FolderBrowserMode.tree,
  }) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => FolderBrowserScreen(
          initialFolder: folder,
          initialMode: mode,
        ),
      ),
    );
  }

  @override
  ConsumerState<FolderBrowserScreen> createState() =>
      _FolderBrowserScreenState();
}

enum FolderBrowserMode { tree, library }

class _FolderBrowserScreenState extends ConsumerState<FolderBrowserScreen> {
  late FolderBrowserMode _mode = widget.initialMode;
  late String _currentFolder = widget.initialFolder;
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Restore the persisted default view type (the initial mode argument is
    // only a fallback while the store hydrates).
    () async {
      final store = ref.read(libraryViewConfigStoreProvider);
      final persisted = await store.readBrowserMode();
      if (!mounted) {
        return;
      }
      setState(() {
        _mode = persisted == 'library'
            ? FolderBrowserMode.library
            : FolderBrowserMode.tree;
      });
    }();
  }

  Future<void> _persistMode(FolderBrowserMode mode) async {
    await ref
        .read(libraryViewConfigStoreProvider)
        .writeBrowserMode(mode == FolderBrowserMode.library ? 'library' : 'tree');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final pathsAsync = ref.watch(libraryFilePathsProvider);
    final visibility = ref.watch(libraryVisibilityProvider);

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Browse folders',
          style: WavelyTypography.title20(color: colors.textPrimary),
        ),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('browser-mode-toggle'),
            icon: Icon(
              _mode == FolderBrowserMode.tree
                  ? Icons.queue_music
                  : Icons.account_tree_outlined,
            ),
            tooltip: _mode == FolderBrowserMode.tree
                ? 'Switch to library view'
                : 'Switch to folder tree',
            onPressed: () {
              setState(() => _mode =
                  _mode == FolderBrowserMode.tree
                      ? FolderBrowserMode.library
                      : FolderBrowserMode.tree);
              unawaited(_persistMode(_mode));
            },
          ),
          IconButton(
            key: const ValueKey<String>('browser-filters-button'),
            icon: const Icon(Icons.tune),
            tooltip: 'Library filters',
            onPressed: _openFilters,
          ),
        ],
      ),
      body: SafeArea(
        child: pathsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => ErrorState(
            message: 'Could not load the folder tree',
            detail: error.toString(),
            onRetry: () => ref.invalidate(libraryFilePathsProvider),
          ),
          data: (paths) => Column(
            children: <Widget>[
              if (_currentFolder.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    Spacing.sm,
                    Spacing.lg,
                    0,
                  ),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        key: const ValueKey<String>('browser-up-button'),
                        icon: Icon(Icons.arrow_upward,
                            color: colors.textSecondary),
                        tooltip: 'Up one level',
                        onPressed: () => setState(() {
                          _currentFolder = FolderTree.parentOf(_currentFolder);
                        }),
                      ),
                      Expanded(
                        child: Text(
                          _currentFolder,
                          style: WavelyTypography.caption12(
                            color: colors.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _mode == FolderBrowserMode.tree
                    ? _buildTree(colors, paths, visibility)
                    : _buildLibrary(colors),
              ),
              QuickSearchBox(
                filterKey: const ValueKey<String>('quick-search-folders'),
                hintText: 'Filter folders…',
                onQueryChanged: (query) => setState(() => _query = query),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTree(
    WavelySemanticColors colors,
    List<String> paths,
    LibraryVisibilityConfig visibility,
  ) {
    final children = FolderTree.childFolders(paths, _currentFolder);
    final visible = <({String name, String path, int trackCount})>[
      for (final child in children)
        if (quickSearchMatches(child.name, _query)) child,
    ];
    if (children.isEmpty && _currentFolder.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_open,
        title: 'No indexed folders',
        subtitle: 'Add a scan folder first — the tree mirrors your library.',
      );
    }
    if (visible.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: _query.isEmpty ? 'Empty folder' : 'No matches',
        subtitle: _query.isEmpty
            ? 'No subfolders with indexed tracks.'
            : 'Nothing matches your filter.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(Spacing.lg),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final child = visible[index];
        final blacklisted = LibraryVisibility.underAny(
          child.path,
          visibility.blacklist,
        );
        return ListTile(
          key: ValueKey<String>('folder-node-${child.path}'),
          leading: Icon(
            blacklisted ? Icons.folder_off_outlined : Icons.folder_outlined,
            color: blacklisted ? colors.error : colors.accentColors.accent,
          ),
          title: Text(
            child.name,
            style: WavelyTypography.body14Medium(color: colors.textPrimary),
          ),
          subtitle: Text(
            blacklisted
                ? 'Hidden by blacklist'
                : '${child.trackCount} '
                    '${child.trackCount == 1 ? 'track' : 'tracks'}',
            style: WavelyTypography.caption12(color: colors.textTertiary),
          ),
          trailing: IconButton(
            icon: Icon(
              blacklisted ? Icons.visibility : Icons.visibility_off,
              color: blacklisted ? colors.error : colors.textTertiary,
            ),
            tooltip: blacklisted
                ? 'Remove from blacklist'
                : 'Hide folder (blacklist)',
            onPressed: () => unawaited(
              _toggleBlacklist(child.path, remove: blacklisted),
            ),
          ),
          onTap: () => setState(() => _currentFolder = child.path),
          onLongPress: () => unawaited(
            FolderBrowserScreen.open(
              context,
              folder: child.path,
              mode: FolderBrowserMode.library,
            ),
          ),
        );
      },
    );
  }

  Widget _buildLibrary(WavelySemanticColors colors) {
    final tracksAsync = ref.watch(folderTracksProvider(_currentFolder));
    return tracksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => ErrorState(
        message: 'Could not load this folder',
        detail: error.toString(),
        onRetry: () =>
            ref.invalidate(folderTracksProvider(_currentFolder)),
      ),
      data: (tracks) {
        final visible = <Track>[
          for (final track in tracks)
            if (quickSearchMatches(track.title, _query) ||
                quickSearchMatches(track.artistOrUnknown, _query))
              track,
        ];
        if (visible.isEmpty) {
          return EmptyState(
            icon: Icons.music_off,
            title: _query.isEmpty ? 'No tracks here' : 'No matches',
            subtitle: _query.isEmpty
                ? 'This folder has no indexed tracks.'
                : 'Nothing matches your filter.',
            ctaLabel: _currentFolder.isEmpty ? null : 'Open folder tree',
            onCta: _currentFolder.isEmpty
                ? null
                : () => setState(
                      () => _mode = FolderBrowserMode.tree,
                    ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(Spacing.lg),
          itemCount: visible.length,
          itemBuilder: (context, index) {
            final track = visible[index];
            return TrackTile(
              key: ValueKey<String>('folder-track-${track.id ?? index}'),
              track: track,
              showSourceBadge: true,
              onTap: () => unawaited(
                ref
                    .read(trackLauncherProvider)
                    .playTracks(List<Track>.of(visible), startIndex: index),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleBlacklist(String folder, {required bool remove}) async {
    final notifier = ref.read(libraryVisibilityProvider.notifier);
    final current = List<String>.of(ref.read(libraryVisibilityProvider).blacklist);
    if (remove) {
      current.removeWhere((entry) => entry == folder);
    } else if (!current.contains(folder)) {
      current.add(folder);
    }
    await notifier.setBlacklist(current);
    ref.invalidate(folderTracksProvider);
    ref.invalidate(libraryFilePathsProvider);
  }

  void _openFilters() {
    final colors = context.wavelyColors;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (context, sheetRef, _) {
          final visibility = sheetRef.watch(libraryVisibilityProvider);
          final notifier = sheetRef.read(libraryVisibilityProvider.notifier);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Library filters',
                    style: WavelyTypography.title20(color: colors.textPrimary),
                  ),
                  const SizedBox(height: Spacing.md),
                  Text(
                    'Ignore tracks shorter than',
                    style: WavelyTypography.body14Medium(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Wrap(
                    spacing: Spacing.sm,
                    children: <Widget>[
                      for (final seconds in const <int>[0, 5, 15, 30, 60])
                        ChoiceChip(
                          key: ValueKey<String>('min-duration-$seconds'),
                          label: Text(seconds == 0 ? 'Off' : '$seconds s'),
                          selected:
                              visibility.minDurationSeconds == seconds,
                          onSelected: (_) {
                            unawaited(notifier.setMinDurationSeconds(seconds));
                            ref.invalidate(folderTracksProvider);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: Spacing.lg),
                  Text(
                    'Blacklisted folders (hidden)',
                    style: WavelyTypography.body14Medium(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  if (visibility.blacklist.isEmpty)
                    Text(
                      'None — long-press folders in the tree to hide them.',
                      style: WavelyTypography.caption12(
                        color: colors.textTertiary,
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: ListView(
                        shrinkWrap: true,
                        children: <Widget>[
                          for (final folder in visibility.blacklist)
                            ListTile(
                              key: ValueKey<String>('blacklist-$folder'),
                              dense: true,
                              leading: Icon(Icons.folder_off_outlined,
                                  color: colors.error),
                              title: Text(
                                folder,
                                style: WavelyTypography.caption12(
                                  color: colors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                tooltip: 'Remove from blacklist',
                                onPressed: () {
                                  unawaited(
                                    _toggleBlacklistFromSheet(
                                      sheetRef,
                                      folder,
                                      remove: true,
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: Spacing.lg),
                  Text(
                    'Whitelist (when set, only these folders show)',
                    style: WavelyTypography.body14Medium(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  _WhitelistEditor(
                    visibility: visibility,
                    onAdd: (path) async {
                      await notifier.setWhitelist(
                        <String>[...visibility.whitelist, path],
                      );
                      ref.invalidate(folderTracksProvider);
                    },
                    onRemove: (path) async {
                      await notifier.setWhitelist(
                        visibility.whitelist.where((f) => f != path).toList(),
                      );
                      ref.invalidate(folderTracksProvider);
                    },
                  ),
                  const SizedBox(height: Spacing.lg),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleBlacklistFromSheet(
    WidgetRef sheetRef,
    String folder, {
    required bool remove,
  }) async {
    final notifier = sheetRef.read(libraryVisibilityProvider.notifier);
    final current =
        List<String>.of(sheetRef.read(libraryVisibilityProvider).blacklist);
    if (remove) {
      current.removeWhere((entry) => entry == folder);
    } else if (!current.contains(folder)) {
      current.add(folder);
    }
    await notifier.setBlacklist(current);
    ref.invalidate(folderTracksProvider);
    ref.invalidate(libraryFilePathsProvider);
  }
}

/// Whitelist editor inside the filter sheet: add via dialog text field,
/// remove per row.
class _WhitelistEditor extends StatefulWidget {
  const _WhitelistEditor({
    required this.visibility,
    required this.onAdd,
    required this.onRemove,
  });

  final LibraryVisibilityConfig visibility;
  final Future<void> Function(String path) onAdd;
  final Future<void> Function(String path) onRemove;

  @override
  State<_WhitelistEditor> createState() => _WhitelistEditorState();
}

class _WhitelistEditorState extends State<_WhitelistEditor> {
  Future<void> _add() async {
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Whitelist folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: '/absolute/music/path'),
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
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (path != null && path.isNotEmpty) {
      await widget.onAdd(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (widget.visibility.whitelist.isEmpty)
          Text(
            'Not set — every blacklisted-allowed folder is shown.',
            style: WavelyTypography.caption12(color: colors.textTertiary),
          )
        else
          for (final folder in widget.visibility.whitelist)
            ListTile(
              key: ValueKey<String>('whitelist-$folder'),
              dense: true,
              leading:
                  Icon(Icons.folder_special_outlined,
                      color: colors.accentColors.accent),
              title: Text(
                folder,
                style: WavelyTypography.caption12(color: colors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove from whitelist',
                onPressed: () => unawaited(widget.onRemove(folder)),
              ),
            ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey<String>('whitelist-add-button'),
            onPressed: () => unawaited(_add()),
            icon: const Icon(Icons.add),
            label: const Text('Add whitelist folder'),
          ),
        ),
      ],
    );
  }
}

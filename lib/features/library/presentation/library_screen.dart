import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/downloads/presentation/downloads_screen.dart';
import 'package:wavely/features/library/data/library_view_config.dart';
import 'package:wavely/features/library/presentation/albums_tab.dart';
import 'package:wavely/features/library/presentation/all_tracks_tab.dart';
import 'package:wavely/features/library/presentation/artists_tab.dart';
import 'package:wavely/features/library/presentation/folders_tab.dart';
import 'package:wavely/features/library/presentation/genres_tab.dart';
import 'package:wavely/features/library/presentation/library_tab_manager.dart';
import 'package:wavely/features/library/presentation/most_played_tab.dart';
import 'package:wavely/features/library/presentation/online_tab.dart';
import 'package:wavely/features/library/presentation/playlists_tab.dart';
import 'package:wavely/features/library/presentation/recently_added_tab.dart';

/// Local library root screen (Phase 6): glassy header with the settings
/// entry point, a nine-tab bar driven by the persisted tab manager
/// (reorder/hide via the manager sheet) and the tab bodies.
///
/// Route: [libraryRoute] (the router's Local branch).
class LibraryScreen extends ConsumerWidget {
  /// Creates the library screen; [onSettingsTap] is optional because the app
  /// shell may own the settings navigation instead.
  const LibraryScreen({super.key, this.onSettingsTap});

  /// Route path for the router's Local branch.
  static const String libraryRoute = '/local';

  final VoidCallback? onSettingsTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final config = ref.watch(libraryTabsProvider);
    final tabs = config.visibleTabs;

    return DefaultTabController(
      key: ValueKey<String>('library-tabs-${tabs.join('-')}'),
      length: tabs.length,
      child: Scaffold(
        backgroundColor: colors.bgBase,
        body: SafeArea(
          child: Column(
            children: [
              GlassCard(
                child: Row(
                  children: [
                    const SizedBox(width: Spacing.lg),
                    Expanded(
                      child: Text(
                        'Local',
                        style: WavelyTypography.title20(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('library-downloads-button'),
                      icon: Icon(Icons.download_rounded,
                          color: colors.textSecondary),
                      tooltip: 'Downloads',
                      onPressed: () =>
                          unawaited(context.push(downloadsRoute)),
                    ),
                    IconButton(
                      key: const Key('library-tab-manager-button'),
                      icon: Icon(Icons.tune, color: colors.textSecondary),
                      tooltip: 'Edit tabs',
                      onPressed: () => _openTabManager(context, ref),
                    ),
                    IconButton(
                      icon: Icon(Icons.settings, color: colors.textSecondary),
                      tooltip: 'Settings',
                      onPressed: onSettingsTap,
                    ),
                    const SizedBox(width: Spacing.sm),
                  ],
                ),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: colors.accentColors.accent,
                labelColor: colors.accentColors.accent,
                unselectedLabelColor: colors.textSecondary,
                dividerColor: colors.borderGlass,
                tabs: <Widget>[
                  for (final tab in tabs)
                    Tab(text: libraryTabMeta[tab]?.label ?? tab.name),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: <Widget>[
                    for (final tab in tabs) _tabBody(tab),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the body for one visible tab id.
  Widget _tabBody(LibraryTabId tab) => switch (tab) {
        LibraryTabId.songs => const AllTracksTab(),
        LibraryTabId.albums => const AlbumsTab(),
        LibraryTabId.artists => const ArtistsTab(),
        LibraryTabId.genres => const GenresTab(),
        LibraryTabId.folders => const FoldersTab(),
        LibraryTabId.playlists => const PlaylistsTab(),
        LibraryTabId.recentlyAdded => const RecentlyAddedTab(),
        LibraryTabId.mostPlayed => const MostPlayedTab(),
        LibraryTabId.online => const OnlineTab(),
      };

  /// Tab manager sheet: reorder (drag), show/hide per tab, reset.
  Future<void> _openTabManager(BuildContext context, WidgetRef ref) async {
    final colors = context.wavelyColors;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (context, sheetRef, _) {
          final config = sheetRef.watch(libraryTabsProvider);
          final notifier = sheetRef.read(libraryTabsProvider.notifier);
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.75,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(Spacing.lg),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Library tabs',
                            style: WavelyTypography.title20(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        TextButton(
                          key: const ValueKey<String>('tabs-reset-button'),
                          onPressed: () =>
                              unawaited(notifier.resetToDefault()),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.lg,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'Drag to reorder. Toggle to show or hide a tab.',
                        style: WavelyTypography.caption12(
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Expanded(
                    child: ReorderableListView.builder(
                      buildDefaultDragHandles: true,
                      itemCount: config.order.length,
                      onReorder: (oldIndex, newIndex) =>
                          unawaited(notifier.reorder(oldIndex, newIndex)),
                      itemBuilder: (context, index) {
                        final tab = config.order[index];
                        final hidden = config.hidden.contains(tab);
                        final meta = libraryTabMeta[tab];
                        return CheckboxListTile(
                          key: ValueKey<String>('tab-row-${tab.name}'),
                          secondary: Icon(
                            meta?.icon ?? Icons.tab,
                            color: hidden
                                ? colors.textTertiary
                                : colors.accentColors.accent,
                          ),
                          title: Text(
                            meta?.label ?? tab.name,
                            style: WavelyTypography.body14Medium(
                              color: hidden
                                  ? colors.textTertiary
                                  : colors.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            hidden ? 'Hidden' : 'Visible',
                            style: WavelyTypography.micro10(
                              color: colors.textTertiary,
                            ),
                          ),
                          value: !hidden,
                          onChanged: (_) =>
                              unawaited(notifier.toggleHidden(tab)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

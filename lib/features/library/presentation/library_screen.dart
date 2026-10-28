import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/library/presentation/all_tracks_tab.dart';
import 'package:wavely/features/library/presentation/albums_tab.dart';
import 'package:wavely/features/library/presentation/artists_tab.dart';
import 'package:wavely/features/library/presentation/folders_tab.dart';
import 'package:wavely/features/library/presentation/genres_tab.dart';

/// Number of library tabs (Folders, Artists, Albums, Genres, All Tracks).
const int _tabCount = 5;

/// Library root screen: glassy header with the settings entry point plus a
/// tab bar over the five library tabs.
///
/// Route: [libraryRoute] (Task 4 registers it with go_router).
class LibraryScreen extends ConsumerWidget {
  /// Creates the library screen; [onSettingsTap] is optional because the app
  /// shell may own the settings navigation instead.
  const LibraryScreen({super.key, this.onSettingsTap});

  /// Route path for Task 4's router.
  static const String libraryRoute = '/library';

  final VoidCallback? onSettingsTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    return DefaultTabController(
      length: _tabCount,
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
                        'Library',
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
                      // Stage 2.1: additive entry point to the download
                      // manager (tab count intentionally unchanged).
                      onPressed: () =>
                          unawaited<void>(context.push(downloadsRoute)),
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
                tabs: const <Widget>[
                  Tab(text: 'Folders'),
                  Tab(text: 'Artists'),
                  Tab(text: 'Albums'),
                  Tab(text: 'Genres'),
                  Tab(text: 'All Tracks'),
                ],
              ),
              const Expanded(
                child: TabBarView(
                  children: <Widget>[
                    FoldersTab(),
                    ArtistsTab(),
                    AlbumsTab(),
                    GenresTab(),
                    AllTracksTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

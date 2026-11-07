import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/library_view_config.dart';
import 'package:wavely/features/library/presentation/album_detail_screen.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';
import 'package:wavely/features/library/presentation/quick_search_box.dart';
import 'package:wavely/features/library/presentation/sort_menu.dart';

/// Fixed width of one album card.
const double _albumCardWidth = 160;

/// Height of the placeholder cells shown while albums load.
const double _shimmerCellHeight = 200;

/// Number of placeholder cells shown while albums load.
const int _shimmerCellCount = 6;

/// Albums tab (Phase 6): album cards with persisted sort memory (name,
/// date added, track count) and a bottom QuickSearchBox.
class AlbumsTab extends ConsumerStatefulWidget {
  /// Creates the albums tab.
  const AlbumsTab({super.key});

  @override
  ConsumerState<AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends ConsumerState<AlbumsTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final sort = ref.watch(sortConfigProvider(LibraryTabId.albums));
    final albumsAsync = ref.watch(albumsProvider);
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[SortMenuButton(tab: LibraryTabId.albums)],
        ),
        Expanded(
          child: albumsAsync.when(
            loading: () => GridView.builder(
              padding: const EdgeInsets.all(Spacing.lg),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: _albumCardWidth,
                mainAxisSpacing: Spacing.md,
                crossAxisSpacing: Spacing.md,
              ),
              itemCount: _shimmerCellCount,
              itemBuilder: (context, index) => const ShimmerBox(
                height: _shimmerCellHeight,
              ),
            ),
            error: (error, stackTrace) => ErrorState(
              message: 'Could not load albums',
              detail: error.toString(),
              onRetry: () => ref.invalidate(albumsProvider),
            ),
            data: (albums) {
              var visible = <Album>[
                for (final album in albums)
                  if (quickSearchMatches(album.title, _query) ||
                      quickSearchMatches(album.artist, _query))
                    album,
              ];
              visible = _sortAlbums(visible, sort);
              if (albums.isEmpty) {
                return const EmptyState(
                  icon: Icons.album_outlined,
                  title: 'No albums yet',
                  subtitle: 'Scan a folder first to fill your library.',
                );
              }
              if (visible.isEmpty) {
                return const EmptyState(
                  icon: Icons.search_off,
                  title: 'No matches',
                  subtitle: 'Nothing matches your filter.',
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  0,
                  Spacing.lg,
                  Spacing.md,
                ),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: _albumCardWidth,
                  mainAxisSpacing: Spacing.md,
                  crossAxisSpacing: Spacing.md,
                ),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final album = visible[index];
                  return AlbumCard(
                    key: ValueKey<String>('album-${album.key}'),
                    title: album.title,
                    artist: album.artist,
                    coverPath: album.coverPath,
                    onTap: () {
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => AlbumDetailScreen(
                            albumTitle: album.title,
                            artistName: album.artist,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        QuickSearchBox(
          filterKey: const ValueKey<String>('quick-search-albums'),
          hintText: 'Filter Albums…',
          onQueryChanged: (query) => setState(() => _query = query),
        ),
      ],
    );
  }

  /// Client-side album ordering by the persisted sort key.
  List<Album> _sortAlbums(List<Album> albums, SortKey sort) {
    final list = List<Album>.of(albums);
    switch (sort) {
      case SortKey.titleAsc:
        list.sort((a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case SortKey.titleDesc:
        list.sort((a, b) =>
            b.title.toLowerCase().compareTo(a.title.toLowerCase()));
      case SortKey.dateAddedAsc:
        list.sort((a, b) => a.addedAt.compareTo(b.addedAt));
      case SortKey.dateAddedDesc:
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case SortKey.trackCountDesc:
        list.sort((a, b) {
          final byCount = b.trackCount.compareTo(a.trackCount);
          if (byCount != 0) {
            return byCount;
          }
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
      case SortKey.artistAsc:
        list.sort((a, b) =>
            a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
      case SortKey.durationAsc:
      case SortKey.durationDesc:
      case SortKey.playCountDesc:
        break;
    }
    return list;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/library_view_config.dart';
import 'package:wavely/features/library/presentation/artist_detail_screen.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';
import 'package:wavely/features/library/presentation/quick_search_box.dart';
import 'package:wavely/features/library/presentation/sort_menu.dart';

/// Grid cell size for the artist circles.
const double _maxCrossAxisExtent = 120;

/// Width/height ratio of one artist grid cell (circle + name caption).
const double _artistCellAspectRatio = 0.85;

/// Radius of the artist circle inside the grid.
const double _artistCircleRadius = 40;

/// Height of the placeholder cells shown while artists load.
const double _shimmerCellHeight = 120;

/// Number of placeholder cells shown while artists load.
const int _shimmerCellCount = 8;

/// Artists tab (Phase 6): artist circles with persisted sort memory (name
/// or track count) and a bottom QuickSearchBox.
class ArtistsTab extends ConsumerStatefulWidget {
  /// Creates the artists tab.
  const ArtistsTab({super.key});

  @override
  ConsumerState<ArtistsTab> createState() => _ArtistsTabState();
}

class _ArtistsTabState extends ConsumerState<ArtistsTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final sort = ref.watch(sortConfigProvider(LibraryTabId.artists));
    final artistsAsync = ref.watch(artistsProvider);
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[SortMenuButton(tab: LibraryTabId.artists)],
        ),
        Expanded(
          child: artistsAsync.when(
            loading: () => GridView.builder(
              padding: const EdgeInsets.all(Spacing.lg),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: _maxCrossAxisExtent,
                childAspectRatio: _artistCellAspectRatio,
                mainAxisSpacing: Spacing.md,
                crossAxisSpacing: Spacing.md,
              ),
              itemCount: _shimmerCellCount,
              itemBuilder: (context, index) => const ShimmerBox(
                height: _shimmerCellHeight,
              ),
            ),
            error: (error, stackTrace) => ErrorState(
              message: 'Could not load artists',
              detail: error.toString(),
              onRetry: () => ref.invalidate(artistsProvider),
            ),
            data: (artists) {
              var visible = <Artist>[
                for (final artist in artists)
                  if (quickSearchMatches(artist.name, _query)) artist,
              ];
              visible = _sortArtists(visible, sort);
              if (artists.isEmpty) {
                return const EmptyState(
                  icon: Icons.person_off_outlined,
                  title: 'No artists yet',
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
                  maxCrossAxisExtent: _maxCrossAxisExtent,
                  childAspectRatio: _artistCellAspectRatio,
                  mainAxisSpacing: Spacing.md,
                  crossAxisSpacing: Spacing.md,
                ),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final artist = visible[index];
                  return Column(
                    children: <Widget>[
                      ArtistCircle(
                        name: artist.name,
                        coverPath: artist.coverPath,
                        radius: _artistCircleRadius,
                        onTap: () {
                          Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ArtistDetailScreen(artistName: artist.name),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        artist.name,
                        style: WavelyTypography.caption12(
                          color: colors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        QuickSearchBox(
          filterKey: const ValueKey<String>('quick-search-artists'),
          hintText: 'Filter Artists…',
          onQueryChanged: (query) => setState(() => _query = query),
        ),
      ],
    );
  }

  /// Client-side artist ordering by the persisted sort key.
  List<Artist> _sortArtists(List<Artist> artists, SortKey sort) {
    final list = List<Artist>.of(artists);
    switch (sort) {
      case SortKey.titleAsc:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case SortKey.titleDesc:
        list.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      case SortKey.trackCountDesc:
        list.sort((a, b) {
          final byCount = b.trackCount.compareTo(a.trackCount);
          if (byCount != 0) {
            return byCount;
          }
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      case SortKey.artistAsc:
      case SortKey.durationAsc:
      case SortKey.durationDesc:
      case SortKey.dateAddedAsc:
      case SortKey.dateAddedDesc:
      case SortKey.playCountDesc:
        break;
    }
    return list;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/library/presentation/artist_detail_screen.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';

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

/// Artists tab: every artist of the library as a circle + name, alphabetical.
class ArtistsTab extends ConsumerWidget {
  /// Creates the artists tab.
  const ArtistsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final artistsAsync = ref.watch(artistsProvider);
    return artistsAsync.when(
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
        if (artists.isEmpty) {
          return const EmptyState(
            icon: Icons.person_off_outlined,
            title: 'No artists yet',
            subtitle: 'Scan a folder first to fill your library.',
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(Spacing.lg),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: _maxCrossAxisExtent,
            childAspectRatio: _artistCellAspectRatio,
            mainAxisSpacing: Spacing.md,
            crossAxisSpacing: Spacing.md,
          ),
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artist = artists[index];
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
    );
  }
}

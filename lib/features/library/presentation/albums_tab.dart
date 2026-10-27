import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/library/presentation/album_detail_screen.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';

/// Fixed width of one album card.
const double _albumCardWidth = 160;

/// Height of the placeholder cells shown while albums load.
const double _shimmerCellHeight = 200;

/// Number of placeholder cells shown while albums load.
const int _shimmerCellCount = 6;

/// Albums tab: album cards, newest first.
class AlbumsTab extends ConsumerWidget {
  /// Creates the albums tab.
  const AlbumsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumsAsync = ref.watch(albumsProvider);
    return albumsAsync.when(
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
        if (albums.isEmpty) {
          return const EmptyState(
            icon: Icons.album_outlined,
            title: 'No albums yet',
            subtitle: 'Scan a folder first to fill your library.',
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(Spacing.lg),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: _albumCardWidth,
            mainAxisSpacing: Spacing.md,
            crossAxisSpacing: Spacing.md,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
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
    );
  }
}

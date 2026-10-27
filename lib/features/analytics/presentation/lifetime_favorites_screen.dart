import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/analytics/data/analytics_repository.dart';

/// All-time favorites (most-played tracks, top 50).
final lifetimeFavoritesProvider = FutureProvider<List<Track>>((ref) async {
  final repo = ref.watch(analyticsRepositoryProvider);
  return repo.getLifetimeFavorites(limit: 50);
});

/// Lifetime favorites screen: the top 50 most-played tracks with a count
/// subtitle.
///
/// Route: `/analytics/favorites` (registered by the orchestrator).
class LifetimeFavoritesScreen extends ConsumerWidget {
  /// Creates the screen.
  const LifetimeFavoritesScreen({super.key});

  /// Route path for the router (registered by the orchestrator).
  static const String route = '/analytics/favorites';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final async = ref.watch(lifetimeFavoritesProvider);
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        title: Text(
          'Lifetime Favorites',
          style: WavelyTypography.title20(color: colors.textPrimary),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          children: <Widget>[
            const SizedBox(height: 120),
            ErrorState(
              message: 'Could not load your favorites',
              onRetry: () => ref.invalidate(lifetimeFavoritesProvider),
            ),
          ],
        ),
        data: (tracks) {
          if (tracks.isEmpty) {
            return ListView(
              children: <Widget>[
                SizedBox(
                  height: 480,
                  child: Center(
                    child: EmptyState(
                      icon: Icons.favorite_outline,
                      title: 'No favorites yet',
                      subtitle:
                          'Tracks you play the most will show up here.',
                    ),
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(Spacing.lg),
            itemCount: tracks.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: Text(
                    '${tracks.length} tracks, ranked by play count',
                    style: WavelyTypography.caption12(
                      color: colors.textSecondary,
                    ),
                  ),
                );
              }
              final track = tracks[index - 1];
              return TrackTile(track: track);
            },
          );
        },
      ),
    );
  }
}

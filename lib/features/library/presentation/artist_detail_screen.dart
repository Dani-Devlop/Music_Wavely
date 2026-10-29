import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';

/// Height of the placeholder rows shown while the artist's tracks load.
const double _shimmerRowHeight = 56;

/// Number of placeholder rows shown while the artist's tracks load.
const int _shimmerRowCount = 6;

/// Radius of the artist circle in the header.
const double _headerCircleRadius = 40;

/// All tracks of one artist, with a play-all button.
class ArtistDetailScreen extends ConsumerWidget {
  /// Creates the detail screen for [artistName] (case-insensitive match).
  const ArtistDetailScreen({required this.artistName, super.key});

  /// Route path for Task 4's router.
  static const String artistRoute = '/library/artist';

  /// Route pattern with the path parameter Task 4 fills in.
  static const String artistRoutePattern = '$artistRoute/:name';

  final String artistName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final tracksAsync = ref.watch(artistTracksProvider(artistName));
    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: tracksAsync.when(
          loading: () => ListView.builder(
            padding: const EdgeInsets.all(Spacing.lg),
            itemCount: _shimmerRowCount,
            itemBuilder: (context, index) => const Padding(
              padding: EdgeInsets.only(bottom: Spacing.sm),
              child: ShimmerBox(height: _shimmerRowHeight),
            ),
          ),
          error: (error, stackTrace) => ErrorState(
            message: 'Could not load "$artistName"',
            detail: error.toString(),
            onRetry: () => ref.invalidate(artistTracksProvider(artistName)),
          ),
          data: (tracks) {
            final albums = <String>{
              for (final track in tracks)
                if (track.album != null) track.album!,
            };
            return Column(
              children: <Widget>[
                GlassCard(
                  child: Row(
                    children: <Widget>[
                      BackButton(color: colors.textPrimary),
                      const SizedBox(width: Spacing.sm),
                      ArtistCircle(
                        name: artistName,
                        coverPath: tracks.firstOrNull?.coverPath,
                        radius: _headerCircleRadius,
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              artistName,
                              style: WavelyTypography.title20(
                                color: colors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${tracks.length} tracks · ${albums.length} albums',
                              style: WavelyTypography.caption12(
                                color: colors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      IconButton.filled(
                        tooltip: 'Play all',
                        icon: const Icon(Icons.play_arrow),
                        color: colors.bgBase,
                        onPressed: tracks.isEmpty
                            ? null
                            : () {
                                unawaited(
                                  ref
                                      .read(trackLauncherProvider)
                                      .playTracks(tracks),
                                );
                              },
                      ),
                      const SizedBox(width: Spacing.sm),
                    ],
                  ),
                ),
                Expanded(
                  child: tracks.isEmpty
                      ? const EmptyState(
                          icon: Icons.music_off_outlined,
                          title: 'No tracks',
                          subtitle: 'This artist has no tracks yet.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            vertical: Spacing.sm,
                          ),
                          itemCount: tracks.length,
                          itemBuilder: (context, index) {
                            final track = tracks[index];
                            return TrackTile(
                              key: ValueKey<String>(
                                'artist-track-${track.id}',
                              ),
                              track: track,
                              showSourceBadge: true,
                              onTap: () {
                                unawaited(
                                  ref
                                      .read(trackLauncherProvider)
                                      .playTracks(tracks, startIndex: index),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

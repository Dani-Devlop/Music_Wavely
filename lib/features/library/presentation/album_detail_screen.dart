import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';
import 'package:wavely/features/library/presentation/local_cover.dart';

/// Height of the placeholder rows shown while the album's tracks load.
const double _shimmerRowHeight = 56;

/// Number of placeholder rows shown while the album's tracks load.
const int _shimmerRowCount = 6;

/// Edge length of the square album cover in the header.
const double _headerCoverSize = 80;

/// All tracks of one album, with a play-all button.
class AlbumDetailScreen extends ConsumerWidget {
  /// Creates the detail screen for the album [albumTitle] by [artistName].
  const AlbumDetailScreen({
    required this.albumTitle,
    required this.artistName,
    super.key,
  });

  /// Route path for Task 4's router.
  static const String albumRoute = '/library/album';

  /// Route pattern with the path parameters Task 4 fills in.
  static const String albumRoutePattern = '$albumRoute/:artist/:album';

  final String albumTitle;

  final String artistName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final params = (artist: artistName, album: albumTitle);
    final tracksAsync = ref.watch(albumTracksProvider(params));
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
            message: 'Could not load "$albumTitle"',
            detail: error.toString(),
            onRetry: () => ref.invalidate(albumTracksProvider(params)),
          ),
          data: (tracks) {
            final cover = localCoverProvider(tracks.firstOrNull?.coverPath);
            return Column(
              children: <Widget>[
                GlassCard(
                  child: Row(
                    children: <Widget>[
                      BackButton(color: colors.textPrimary),
                      const SizedBox(width: Spacing.sm),
                      Container(
                        width: _headerCoverSize,
                        height: _headerCoverSize,
                        decoration: BoxDecoration(
                          color: colors.elevated,
                          borderRadius: AppRadii.bMd,
                          image: cover == null
                              ? null
                              : DecorationImage(
                                  image: cover,
                                  fit: BoxFit.cover,
                                ),
                        ),
                        child: cover == null
                            ? Icon(
                                Icons.album,
                                color: colors.textTertiary,
                                size: _headerCoverSize / 2,
                              )
                            : null,
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              albumTitle,
                              style: WavelyTypography.title20(
                                color: colors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '$artistName · ${tracks.length} tracks',
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
                          subtitle: 'This album has no tracks yet.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            vertical: Spacing.sm,
                          ),
                          itemCount: tracks.length,
                          itemBuilder: (context, index) {
                            final track = tracks[index];
                            return TrackTile(
                              key: ValueKey<String>('album-track-${track.id}'),
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

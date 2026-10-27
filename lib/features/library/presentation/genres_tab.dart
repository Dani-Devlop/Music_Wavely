import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';

/// Height of the placeholder rows shown while genres load.
const double _shimmerRowHeight = 40;

/// Height of the placeholder track rows shown while a genre's tracks load.
const double _listShimmerRowHeight = 56;

/// Number of placeholder track rows shown while a genre's tracks load.
const int _listShimmerRowCount = 6;

/// Genres tab: genre chips on top; tapping one filters the track list below.
class GenresTab extends ConsumerStatefulWidget {
  /// Creates the genres tab.
  const GenresTab({super.key});

  @override
  ConsumerState<GenresTab> createState() => _GenresTabState();
}

class _GenresTabState extends ConsumerState<GenresTab> {
  String? _selectedGenre;

  void _select(String? genre) {
    setState(() {
      _selectedGenre = _selectedGenre == genre ? null : genre;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final genresAsync = ref.watch(genresProvider);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.md,
            Spacing.lg,
            Spacing.sm,
          ),
          child: genresAsync.when(
            loading: () => const ShimmerBox(height: _shimmerRowHeight),
            error: (error, stackTrace) => Text(
              'Could not load genres: $error',
              style: WavelyTypography.caption12(color: colors.error),
            ),
            data: (genres) {
              if (genres.isEmpty) {
                return Text(
                  'No genres yet — scan a folder first.',
                  style: WavelyTypography.caption12(
                    color: colors.textTertiary,
                  ),
                );
              }
              return Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.xs,
                children: <Widget>[
                  for (final genre in genres)
                    ChipFilter(
                      key: ValueKey<String>('genre-$genre'),
                      label: genre,
                      selected: _selectedGenre == genre,
                      onSelected: (selected) {
                        _select(selected ? genre : null);
                      },
                    ),
                ],
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _selectedGenre == null
              ? const EmptyState(
                  icon: Icons.style_outlined,
                  title: 'Pick a genre',
                  subtitle: 'Tap a genre chip above to see its tracks.',
                )
              : _GenreTrackList(genre: _selectedGenre!),
        ),
      ],
    );
  }
}

class _GenreTrackList extends ConsumerWidget {
  const _GenreTrackList({required this.genre});

  final String genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(genreTracksProvider(genre));
    return tracksAsync.when(
      loading: () => ListView.builder(
        padding: const EdgeInsets.all(Spacing.lg),
        itemCount: _listShimmerRowCount,
        itemBuilder: (context, index) => const Padding(
          padding: EdgeInsets.only(bottom: Spacing.sm),
          child: ShimmerBox(height: _listShimmerRowHeight),
        ),
      ),
      error: (error, stackTrace) => ErrorState(
        message: 'Could not load tracks for "$genre"',
        detail: error.toString(),
        onRetry: () => ref.invalidate(genreTracksProvider(genre)),
      ),
      data: (tracks) {
        if (tracks.isEmpty) {
          return const EmptyState(
            icon: Icons.music_off_outlined,
            title: 'Nothing here',
            subtitle: 'No tracks carry this genre tag yet.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            return TrackTile(
              key: ValueKey<int>('genre-track-${track.id}'),
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
        );
      },
    );
  }
}

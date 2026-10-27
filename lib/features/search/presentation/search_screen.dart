import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/features/search/presentation/search_providers.dart';

/// Height of the horizontal artist row (circle + breathing room).
const double _artistRowHeight = 72;

/// Height of the horizontal album card row (estimated card height for the
/// fixed-width 160 card with cover and captions).
const double _albumRowHeight = 210;

/// Height of the placeholder rows shown while searching.
const double _shimmerRowHeight = 56;

/// Number of placeholder rows shown while searching.
const int _shimmerRowCount = 5;

/// Local library search screen.
///
/// Route: [route] (`/search`, registered by Task 4's router). Queries are
/// debounced by [SearchResultsController] and run against the FTS5 index.
class SearchScreen extends ConsumerStatefulWidget {
  /// Creates the search screen.
  const SearchScreen({super.key});

  /// Route path for Task 4's router.
  static const String route = '/search';

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String text) {
    ref
        .read(searchResultsControllerProvider.notifier)
        .onQueryChanged(text);
  }

  void _playFrom(List<Track> tracks, int index) {
    unawaited(
      ref
          .read(trackLauncherProvider)
          .playTracks(List<Track>.of(tracks), startIndex: index),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final state = ref.watch(searchResultsControllerProvider);
    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: TextField(
                controller: _controller,
                autofocus: false,
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  hintText: 'Search tracks, artists, albums',
                  prefixIcon: Icon(Icons.search, color: colors.textSecondary),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close, color: colors.textTertiary),
                          tooltip: 'Clear',
                          onPressed: () {
                            _controller.clear();
                            _onQueryChanged('');
                          },
                        ),
                ),
              ),
            ),
            Expanded(child: _buildResults(context, state)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, SearchUiState state) {
    if (state.loading && state.results.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.all(Spacing.lg),
        itemCount: _shimmerRowCount,
        itemBuilder: (context, index) => const Padding(
          padding: EdgeInsets.only(bottom: Spacing.sm),
          child: ShimmerBox(height: _shimmerRowHeight),
        ),
      );
    }
    if (state.error != null) {
      return ErrorState(
        message: 'Search failed',
        detail: state.error,
        onRetry: () {
          ref.read(searchResultsControllerProvider.notifier).retry();
        },
      );
    }
    if (state.query.isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        title: 'Search your library',
        subtitle: 'Find tracks, artists and albums you already have.',
      );
    }
    final results = state.results;
    if (results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'No results for "${state.query}"',
        subtitle: 'Try a shorter or different spelling.',
      );
    }
    return _ResultsList(
      results: results,
      onPlay: _playFrom,
    );
  }
}

/// Heterogeneous result list (builder-based, no full column):
/// Tracks header + up to [AppConstants.ftsPageSize] tiles, then one header +
/// one horizontal row each for artists and albums.
class _ResultsList extends ConsumerWidget {
  const _ResultsList({required this.results, required this.onPlay});

  final SearchResults results;

  final void Function(List<Track> tracks, int index) onPlay;

  int get _trackCount =>
      results.tracks.length.clamp(0, AppConstants.ftsPageSize);

  int get _artistSectionCount => results.artists.isEmpty ? 0 : 2;

  int get _albumSectionCount => results.albums.isEmpty ? 0 : 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackHeader = results.tracks.isEmpty ? 0 : 1;
    final itemCount = trackHeader +
        _trackCount +
        _artistSectionCount +
        _albumSectionCount;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: Spacing.xl),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        var cursor = 0;
        if (trackHeader == 1) {
          if (index == cursor) {
            return const _SectionPadding(
              child: SectionHeader(title: 'Tracks'),
            );
          }
          cursor++;
          if (index < cursor + _trackCount) {
            final trackIndex = index - cursor;
            final track = results.tracks[trackIndex];
            return TrackTile(
              key: ValueKey<int>('search-track-${track.id}'),
              track: track,
              showSourceBadge: true,
              onTap: () {
                onPlay(results.tracks, trackIndex);
              },
            );
          }
          cursor += _trackCount;
        }
        if (_artistSectionCount > 0) {
          if (index == cursor) {
            return const _SectionPadding(
              child: SectionHeader(title: 'Artists'),
            );
          }
          cursor++;
          if (index == cursor) {
            return SizedBox(
              height: _artistRowHeight,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                scrollDirection: Axis.horizontal,
                itemCount: results.artists.length,
                itemBuilder: (context, artistIndex) {
                  final artist = results.artists[artistIndex];
                  return Padding(
                    padding: const EdgeInsets.only(right: Spacing.lg),
                    child: ArtistCircle(
                      name: artist.name,
                      coverPath: artist.coverPath,
                      onTap: () {
                        // Task 4 routes this to the artist detail screen.
                      },
                    ),
                  );
                },
              ),
            );
          }
          cursor++;
        }
        if (_albumSectionCount > 0) {
          if (index == cursor) {
            return const _SectionPadding(
              child: SectionHeader(title: 'Albums'),
            );
          }
          cursor++;
          if (index == cursor) {
            return SizedBox(
              height: _albumRowHeight,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                scrollDirection: Axis.horizontal,
                itemCount: results.albums.length,
                itemBuilder: (context, albumIndex) {
                  final album = results.albums[albumIndex];
                  return Padding(
                    padding: const EdgeInsets.only(right: Spacing.lg),
                    child: AlbumCard(
                      title: album.title,
                      artist: album.artist,
                      coverPath: album.coverPath,
                      onTap: () {
                        // Task 4 routes this to the album detail screen.
                      },
                    ),
                  );
                },
              ),
            );
          }
        }
        // Unreachable: itemCount matches the section layout above.
        return const SizedBox.shrink();
      },
    );
  }
}

class _SectionPadding extends StatelessWidget {
  const _SectionPadding({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.xs,
      ),
      child: child,
    );
  }
}

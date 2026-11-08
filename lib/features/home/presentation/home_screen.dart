import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/components/wavely_cover.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/discovery/presentation/discovery_screen.dart';
import 'package:wavely/features/downloads/presentation/downloads_screen.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/features/library/presentation/album_detail_screen.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';
import 'package:wavely/features/news/presentation/news_screen.dart'
    show newsRoute;

/// Height of the "Jump back in" / "Made for you" cover-card rows.
const double _recentRowHeight = 172;

/// Diameter of the small header logo tile (WavelyLogo in the app bar).
const double _headerLogoSize = 30;

/// Home (Playlist) tab — the Spotify-style main page.
///
/// v1.0.1-beta3 owner spec: a branded Wavely header (logo in the app bar),
/// a time-aware greeting, a 2×N grid of recent albums rendered with their
/// REAL album art (never a letter tile) and horizontal carousels for
/// "Made for you" (most played) and "Jump back in" (recently played).
/// Everything is local-first: the screen renders fully offline and only
/// ever queues tracks the user already owns.
class HomeScreen extends ConsumerWidget {
  /// Creates the home screen.
  const HomeScreen({super.key});

  /// Route path for the app router's home branch.
  static const String route = '/home';

  void _play(WidgetRef ref, List<Track> tracks, {int startIndex = 0}) {
    unawaited(
      ref
          .read(trackLauncherProvider)
          .playTracks(List<Track>.of(tracks), startIndex: startIndex),
    );
  }

  void _openAlbum(BuildContext context, Album album) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AlbumDetailScreen(
          albumTitle: album.title,
          artistName: album.artist,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final countAsync = ref.watch(libraryCountProvider);
    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: countAsync.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(Spacing.lg),
            children: const <Widget>[
              ShimmerBox(height: 120),
              SizedBox(height: Spacing.lg),
              ShimmerBox(height: _recentRowHeight),
            ],
          ),
          error: (error, stackTrace) => ErrorState(
            message: 'Could not load your library snapshot',
            detail: error.toString(),
            onRetry: () => ref.invalidate(libraryCountProvider),
          ),
          data: (count) {
            if (count == 0) {
              return _homeEmpty(context);
            }
            return _homeContent(context, ref);
          },
        ),
      ),
    );
  }

  Widget _homeEmpty(BuildContext context) {
    final colors = context.wavelyColors;
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: <Widget>[
        _brandHeader(colors),
        _greeting(colors),
        const SizedBox(height: Spacing.huge),
        EmptyState(
          icon: Icons.waves_rounded,
          title: 'Your library is empty',
          subtitle: 'Scan a folder with your own audio files and your '
              'recently played tracks and mixes will appear here.',
          ctaLabel: 'Browse Local',
          onCta: () => GoRouter.of(context).go('/local'),
        ),
        const SizedBox(height: Spacing.huge),
      ],
    );
  }

  Widget _homeContent(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    return ListView(
      padding: const EdgeInsets.only(bottom: Spacing.xxl),
      children: <Widget>[
        _brandHeader(colors),
        _greeting(colors),
        const SizedBox(height: Spacing.lg),
        _quickLinks(context),
        _albumsGrid(context, ref),
        _recentSection(context, ref),
        _madeForYouSection(context, ref),
        _mixesSection(context, ref),
      ],
    );
  }

  /// The Home app bar: the Wavely logo (Phase 12 brand SVG) beside the
  /// wordmark — owner spec: the logo must be visible on the Home screen.
  Widget _brandHeader(WavelySemanticColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.lg,
        Spacing.lg,
        0,
      ),
      child: Row(
        children: <Widget>[
          const WavelyLogo(size: _headerLogoSize),
          const SizedBox(width: Spacing.sm),
          Text(
            'Wavely',
            style: WavelyTypography.title20(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _greeting(WavelySemanticColors colors) {
    final hour = DateTime.now().hour;
    final greeting = hour < 5
        ? 'Late night listening'
        : hour < 12
            ? 'Good morning'
            : hour < 18
                ? 'Good afternoon'
                : 'Good evening';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.lg,
        Spacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            greeting,
            style: WavelyTypography.display24(color: colors.textPrimary),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'Your library, your rules — offline first.',
            style: WavelyTypography.body14(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _quickLinks(BuildContext context) {
    final colors = context.wavelyColors;
    Widget linkCard({
      required String label,
      required IconData icon,
      required String tooltip,
      required VoidCallback onTap,
    }) =>
        Expanded(
          child: Semantics(
            button: true,
            label: tooltip,
            child: InkWell(
              borderRadius: AppRadii.bLg,
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadii.bLg,
                  border: Border.all(color: colors.borderGlass),
                ),
                child: Column(
                  children: <Widget>[
                    Icon(icon, color: colors.accentColors.accent),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      label,
                      style: WavelyTypography.caption12(
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Row(
        children: <Widget>[
          linkCard(
            label: 'Discovery',
            icon: Icons.explore_rounded,
            tooltip: 'Open discovery',
            onTap: () => GoRouter.of(context).push(DiscoveryScreen.route),
          ),
          const SizedBox(width: Spacing.sm),
          linkCard(
            label: 'Downloads',
            icon: Icons.download_rounded,
            tooltip: 'Open downloads',
            onTap: () => GoRouter.of(context).push(downloadsRoute),
          ),
          const SizedBox(width: Spacing.sm),
          linkCard(
            label: 'News',
            icon: Icons.newspaper_rounded,
            tooltip: 'Open news',
            onTap: () => GoRouter.of(context).push(newsRoute),
          ),
        ],
      ),
    );
  }

  /// "Your top albums": the newest six albums in a 2-per-row grid, each
  /// rendered with its REAL cover art ([Album.coverPath] resolves to the
  /// extracted embedded artwork) and opened in the album detail screen.
  Widget _albumsGrid(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final albumsAsync = ref.watch(albumsProvider);
    return albumsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (albums) {
        if (albums.isEmpty) {
          return const SizedBox.shrink();
        }
        final visible = albums.take(6).toList(growable: false);
        // 2 columns × 3 rows of square covers — the Spotify "good evening"
        // mosaic, with real art instead of letter tiles.
        final rows = <Widget>[
          for (var i = 0; i < visible.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _albumTile(
                      context,
                      colors,
                      visible[i],
                      isLeading: true,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  if (i + 1 < visible.length)
                    Expanded(
                      child: _albumTile(
                        context,
                        colors,
                        visible[i + 1],
                        isLeading: false,
                      ),
                    )
                  else
                    const Expanded(child: SizedBox.shrink()),
                ],
              ),
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: Spacing.xl),
            const SectionHeader(title: 'Your top albums'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Column(children: rows),
            ),
          ],
        );
      },
    );
  }

  Widget _albumTile(
    BuildContext context,
    WavelySemanticColors colors,
    Album album, {
    required bool isLeading,
  }) {
    final keySuffix = isLeading ? 'l' : 'r';
    return Semantics(
      button: true,
      label: 'Open album ${album.title}',
      child: InkWell(
        key: ValueKey<String>('home-album-$keySuffix-${album.key}'),
        borderRadius: AppRadii.bMd,
        onTap: () => _openAlbum(context, album),
        child: Container(
          height: 64,
          padding: const EdgeInsetsDirectional.only(end: Spacing.xs),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: AppRadii.bMd,
            border: Border.all(color: colors.borderGlass),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 64,
                height: 64,
                child: ClipRRect(
                  borderRadius: const BorderRadiusDirectional.only(
                    topStart: Radius.circular(12),
                    bottomStart: Radius.circular(12),
                  ),
                  child: _art(album.coverPath, album.title),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  album.title,
                  style: WavelyTypography.body14Medium(
                    color: colors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Real artwork when a cover file exists; hash-gradient + white note
  /// otherwise (owner spec: never a letter box).
  Widget _art(String? coverPath, String seed) {
    final provider = wavelyCoverProvider(coverPath);
    if (provider != null) {
      return Image(
        image: provider,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => WavelyCoverFallback(label: seed),
      );
    }
    return WavelyCoverFallback(label: seed);
  }

  Widget _recentSection(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final recentAsync = ref.watch(recentlyPlayedProvider);
    return recentAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (tracks) {
        if (tracks.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: Spacing.xl),
            const SectionHeader(title: 'Jump back in'),
            SizedBox(
              height: _recentRowHeight,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                scrollDirection: Axis.horizontal,
                itemCount: tracks.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: Spacing.sm),
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return StaggeredAppear(
                    index: index,
                    child: _RecentCard(
                      track: track,
                      colors: colors,
                      onTap: () => _play(ref, tracks, startIndex: index),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// "Made for you": the user's most-played tracks as a horizontal
  /// carousel of real-art cards (Spotify-style shelf).
  Widget _madeForYouSection(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final mostPlayedAsync = ref.watch(mostPlayedPagedProvider(0));
    return mostPlayedAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (tracks) {
        if (tracks.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: Spacing.xl),
            const SectionHeader(title: 'Made for you'),
            SizedBox(
              height: _recentRowHeight,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                scrollDirection: Axis.horizontal,
                itemCount: tracks.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: Spacing.sm),
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return StaggeredAppear(
                    index: index,
                    child: _RecentCard(
                      track: track,
                      colors: colors,
                      onTap: () => _play(ref, tracks, startIndex: index),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _mixesSection(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final genresAsync = ref.watch(topGenresProvider);
    return genresAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (genres) {
        if (genres.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: Spacing.xl),
            const SectionHeader(title: 'Mixes for you'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: <Widget>[
                  for (var i = 0; i < genres.length; i++)
                    StaggeredAppear(
                      index: i,
                      child: _MixCard(
                        genre: genres[i].genre,
                        trackCount: genres[i].trackCount,
                        colors: colors,
                        onTap: () async {
                          final dao = ref.read(databaseProvider).tracksDao;
                          final tracks = await dao.byGenre(genres[i].genre);
                          if (tracks.isNotEmpty) {
                            _play(ref, tracks);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Vertical cover card for one track (real artwork + title/artist).
class _RecentCard extends StatelessWidget {
  const _RecentCard({
    required this.track,
    required this.colors,
    required this.onTap,
  });

  final Track track;
  final WavelySemanticColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Play ${track.title}',
      child: InkWell(
        borderRadius: AppRadii.bLg,
        onTap: onTap,
        child: SizedBox(
          width: 132,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 132,
                height: 116,
                child: ClipRRect(
                  borderRadius: AppRadii.bLg,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      _art(track.coverPath, track.title),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: colors.borderGlass),
                            borderRadius: AppRadii.bLg,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                track.title,
                style: WavelyTypography.body14Medium(
                  color: colors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                track.artist,
                style: WavelyTypography.caption12(
                  color: colors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _art(String? coverPath, String seed) {
    final provider = wavelyCoverProvider(coverPath);
    if (provider != null) {
      return Image(
        image: provider,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => WavelyCoverFallback(label: seed),
      );
    }
    return WavelyCoverFallback(label: seed);
  }
}

/// Pill-shaped quick-mix card for one genre.
class _MixCard extends StatelessWidget {
  const _MixCard({
    required this.genre,
    required this.trackCount,
    required this.colors,
    required this.onTap,
  });

  final String genre;
  final int trackCount;
  final WavelySemanticColors colors;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final accent = colors.accentColors;
    return Semantics(
      button: true,
      label: 'Play $genre mix',
      child: InkWell(
        borderRadius: AppRadii.bLg,
        onTap: () => unawaited(onTap()),
        child: Container(
          width: 168,
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: AppRadii.bLg,
            border: Border.all(color: colors.borderGlass),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: AppRadii.bMd,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[accent.accent, accent.gradientStart],
                  ),
                ),
                child: const Icon(
                  Icons.queue_music_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '$genre Mix',
                      style: WavelyTypography.body14Medium(
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$trackCount tracks',
                      style: WavelyTypography.caption12(
                        color: colors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/discovery/presentation/discovery_screen.dart';
import 'package:wavely/features/downloads/presentation/downloads_screen.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';
import 'package:wavely/features/library/presentation/library_screen.dart';
import 'package:wavely/features/news/presentation/news_screen.dart'
    show newsRoute;

/// Height of the "Jump back in" cover-card row.
const double _recentRowHeight = 172;

/// Home tab: greeting, "Jump back in" (recently played), quick mixes built
/// from the library's top genres and one-tap links into the online
/// surfaces. Everything is local-first: the screen renders fully offline
/// and only ever queues tracks the user already owns.
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
        _greeting(colors),
        const SizedBox(height: Spacing.huge),
        EmptyState(
          icon: Icons.waves_rounded,
          title: 'Your library is empty',
          subtitle: 'Scan a folder with your own audio files and your '
              'recently played tracks and mixes will appear here.',
          ctaLabel: 'Browse Local',
          onCta: () => GoRouter.of(context).go(LibraryScreen.libraryRoute),
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
        _greeting(colors),
        const SizedBox(height: Spacing.lg),
        _quickLinks(context),
        _recentSection(context, ref),
        _mixesSection(context, ref),
      ],
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

/// Vertical cover card for one recently played track.
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
    final accent = colors.accentColors;
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
              Container(
                width: 132,
                height: 116,
                decoration: BoxDecoration(
                  borderRadius: AppRadii.bLg,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      accent.gradientStart.withValues(alpha: 0.85),
                      accent.accent.withValues(alpha: 0.65),
                    ],
                  ),
                  border: Border.all(color: colors.borderGlass),
                ),
                child: Icon(
                  Icons.music_note_rounded,
                  size: 36,
                  color: colors.textPrimary.withValues(alpha: 0.9),
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

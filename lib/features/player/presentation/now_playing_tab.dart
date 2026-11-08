import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/player/presentation/now_playing_screen.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

/// The "Now Playing" bottom-tab destination (v1.0.1-beta3: the shell has
/// exactly four tabs — Playlist / Now Playing / Search / Settings).
///
/// With a live queue it renders the full [NowPlayingScreen] inline (the
/// same player the mini-player expands to, embedded instead of pushed);
/// with an empty queue it shows a branded empty state that funnels the
/// user to the Search tab's library.
class NowPlayingTab extends ConsumerWidget {
  /// Creates the now-playing tab screen.
  const NowPlayingTab({super.key});

  /// Route path for the app router's now-playing branch.
  static const String route = '/player';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTrack = ref.watch(
      queueManagerProvider.select((state) => state.currentTrack != null),
    );
    if (hasTrack) {
      // The full player, embedded (no route push): the bottom nav and mini
      // player stay visible — this is a destination, not an overlay.
      return const NowPlayingScreen();
    }
    return _NowPlayingEmptyState();
  }
}

/// Branded empty state for the Now Playing tab (no track queued yet).
class _NowPlayingEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Scaffold(
      backgroundColor: colors.bgBase,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const WavelyLogo(size: 88),
              const SizedBox(height: Spacing.xl),
              Text(
                'Nothing playing',
                style: WavelyTypography.title20(color: colors.textPrimary),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'Pick a song from your playlist or library and it will '
                'spin up here.',
                textAlign: TextAlign.center,
                style: WavelyTypography.body14(color: colors.textSecondary),
              ),
              const SizedBox(height: Spacing.xl),
              FilledButton.icon(
                key: const Key('now-playing-empty-browse'),
                onPressed: () => GoRouter.of(context).go('/search'),
                icon: const Icon(Icons.search_rounded),
                label: const Text('Find music'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Desktop (Spotify-clone) now-playing body (v1.0.2, width >= 800).
///
/// Owner spec: when a song is playing, the center view shows a beautiful
/// animated background (blurred album art) with a large cover, the title
/// and the lyrics. Two-column layout: cover + meta on the left, synced
/// lyrics on the right (collapsible to cover-only).
library;

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/core/extensions/duration_x.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/design_system/components/wavely_cover_widget.dart';
import 'package:wavely/features/lyrics/presentation/lyrics_view.dart';
import 'package:wavely/features/player/presentation/musicolet_palette.dart'
    show MusicoletColors;
import 'package:wavely/features/player/presentation/queue_manager_sheet.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

/// Desktop now-playing view bound to the queue state.
class DesktopNowPlayingBody extends ConsumerStatefulWidget {
  const DesktopNowPlayingBody({super.key});

  @override
  ConsumerState<DesktopNowPlayingBody> createState() =>
      _DesktopNowPlayingBodyState();
}

class _DesktopNowPlayingBodyState extends ConsumerState<DesktopNowPlayingBody> {
  bool _showLyrics = true;

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(queueManagerProvider.notifier);
    final queue = ref.watch(queueManagerProvider);
    final engine = ref.watch(playbackEngineProvider);
    final track = queue.currentTrack;
    if (track == null) {
      return const Center(
        child: EmptyState(icon: Icons.music_off, title: 'Nothing playing'),
      );
    }
    final isPlaying = queue.playbackState == PlaybackState.playing;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Animated blurred album-art backdrop.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 900),
          child: KeyedSubtree(
            key: ValueKey<String>('np-bg-${track.sourceTrackId}'),
            child: _BlurredArtBackdrop(coverPath: track.coverPath),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Height-adaptive hero cover: at short desktop windows the
              // cover shrinks instead of overflowing the column.
              final coverSize = (constraints.maxHeight * 0.42).clamp(
                160.0,
                320.0,
              );
              return Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Now playing',
                      style: WavelyTypography.title18(color: Colors.white),
                    ),
                    const SizedBox(height: Spacing.lg),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          // -- cover + meta --------------------------------
                          Expanded(
                            flex: 2,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                SizedBox(
                                  width: coverSize,
                                  height: coverSize,
                                  child: WavelyCover(
                                    label: track.title,
                                    coverPath: track.coverPath,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                const SizedBox(height: Spacing.xl),
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: WavelyTypography.display24(
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: Spacing.xs),
                                Text(
                                  '${track.artistOrUnknown}'
                                  '${track.album?.isNotEmpty == true ? ' · ${track.album}' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: WavelyTypography.body14(
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // -- lyrics --------------------------------------
                          if (_showLyrics)
                            Expanded(
                              flex: 3,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: Spacing.xl,
                                ),
                                child: LyricsView(
                                  track: track,
                                  positionStream: engine.positionStream,
                                  onSeek: manager.seek,
                                  height: double.infinity,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Spacing.lg),
                    // -- seekbar ----------------------------------------------
                    _DesktopSeekbar(queue: queue, onSeek: manager.seek),
                    const SizedBox(height: Spacing.sm),
                    // -- controls ---------------------------------------------
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        IconButton(
                          tooltip: 'Lyrics',
                          onPressed: () =>
                              setState(() => _showLyrics = !_showLyrics),
                          color: _showLyrics
                              ? MusicoletColors.green
                              : Colors.white70,
                          icon: const Icon(Icons.lyrics_outlined),
                        ),
                        IconButton(
                          tooltip: 'Queue',
                          onPressed: () =>
                              unawaited(showQueueManagerSheet(context)),
                          color: Colors.white70,
                          icon: const Icon(Icons.queue_music_rounded),
                        ),
                        const SizedBox(width: Spacing.lg),
                        IconButton(
                          tooltip: 'Shuffle',
                          onPressed: () => unawaited(manager.toggleShuffle()),
                          color: queue.shuffleEnabled
                              ? MusicoletColors.green
                              : Colors.white70,
                          icon: const Icon(Icons.shuffle_rounded),
                        ),
                        IconButton(
                          tooltip: 'Previous',
                          onPressed: () => unawaited(manager.previous()),
                          color: Colors.white,
                          iconSize: 36,
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                        Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            tooltip: 'Play or pause',
                            onPressed: () =>
                                unawaited(manager.togglePlayPause()),
                            color: Colors.black,
                            iconSize: 36,
                            icon: Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next',
                          onPressed: () => unawaited(manager.next()),
                          color: Colors.white,
                          iconSize: 36,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                        IconButton(
                          tooltip: 'Repeat',
                          onPressed: () =>
                              manager.setRepeatMode(switch (queue.repeatMode) {
                                RepeatMode.off => RepeatMode.all,
                                RepeatMode.all => RepeatMode.one,
                                RepeatMode.one => RepeatMode.off,
                              }),
                          color: queue.repeatMode == RepeatMode.off
                              ? Colors.white70
                              : MusicoletColors.green,
                          icon: Icon(
                            queue.repeatMode == RepeatMode.one
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Blurred, slowly-animating album-art backdrop (desktop spec).
class _BlurredArtBackdrop extends StatelessWidget {
  const _BlurredArtBackdrop({required this.coverPath});

  final String? coverPath;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        WavelyCover(
          label: 'backdrop',
          coverPath: coverPath,
          borderRadius: BorderRadius.zero,
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Container(color: Colors.black.withValues(alpha: 0.45)),
        ),
      ],
    );
  }
}

class _DesktopSeekbar extends StatelessWidget {
  const _DesktopSeekbar({required this.queue, required this.onSeek});

  final QueueState queue;
  final Future<void> Function(Duration) onSeek;

  @override
  Widget build(BuildContext context) {
    final durationMs = queue.duration.inMilliseconds;
    final positionMs = queue.position.inMilliseconds;
    final value = durationMs <= 0
        ? 0.0
        : (positionMs / durationMs).clamp(0.0, 1.0).toDouble();
    return Row(
      children: <Widget>[
        Text(
          queue.position.hm,
          style: WavelyTypography.timerTabular(color: Colors.white70),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value,
              activeColor: Colors.white,
              inactiveColor: Colors.white24,
              onChanged: durationMs <= 0
                  ? null
                  : (v) => unawaited(
                      onSeek(Duration(milliseconds: (v * durationMs).round())),
                    ),
            ),
          ),
        ),
        Text(
          queue.duration.hm,
          style: WavelyTypography.timerTabular(color: Colors.white70),
        ),
      ],
    );
  }
}

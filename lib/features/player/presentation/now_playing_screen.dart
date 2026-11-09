import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wavely/app/layout_breakpoints.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/extensions/extensions.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/design_system/components/wavely_cover_widget.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/lyrics/presentation/lyrics_view.dart';
import 'package:wavely/features/player/presentation/now_playing_desktop.dart';
import 'package:wavely/features/player/presentation/queue_sheet.dart';
import 'package:wavely/features/player/presentation/equalizer_screen.dart';
import 'package:wavely/features/player/presentation/musicolet_palette.dart';
import 'package:wavely/features/player/presentation/musicolet_dialogs.dart';
import 'package:wavely/features/player/presentation/song_options_sheet.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

/// Full-screen now-playing view, platform-adaptive (v1.0.2):
///
/// - **width < 800** (Android / Musicolet clone): solid black background,
///   massive cover art, Title / Artist / Album, the icon row
///   (Heart · Info · Add to queue · 3-dots), seekbar and the Musicolet
///   transport row (Rewind · Prev · Play · Next · FF · EQ).
/// - **width >= 800** (Desktop / Spotify clone): animated blurred
///   album-art backdrop, large cover, title and lyrics — see
///   [DesktopNowPlayingBody].
///
/// Reads everything from [queueManagerProvider]; the engine (and therefore
/// its position stream) comes from [playbackEngineProvider], both of which
/// tests override with fakes.
class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  static const String route = '/now-playing';

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(queueManagerProvider);
    final track = queue.currentTrack;
    final colors = context.wavelyColors;
    if (track == null) {
      return Scaffold(
        backgroundColor: isDesktopLayout(MediaQuery.sizeOf(context).width)
            ? colors.bgBase
            : Colors.black,
        body: const Center(
          child: EmptyState(icon: Icons.music_off, title: 'Nothing playing'),
        ),
      );
    }
    if (isDesktopLayout(MediaQuery.sizeOf(context).width)) {
      return Scaffold(
        backgroundColor: colors.bgBase,
        body: const DesktopNowPlayingBody(),
      );
    }
    return _MusicoletNowPlaying(track: track);
  }
}

// ---------------------------------------------------------------------------
// ANDROID — Musicolet clone (solid black, no glassmorphism)
// ---------------------------------------------------------------------------

class _MusicoletNowPlaying extends ConsumerStatefulWidget {
  const _MusicoletNowPlaying({required this.track});

  final Track track;

  @override
  ConsumerState<_MusicoletNowPlaying> createState() =>
      _MusicoletNowPlayingState();
}

class _MusicoletNowPlayingState extends ConsumerState<_MusicoletNowPlaying> {
  static const double _playButtonSize = 76;
  static const double _skipIconSize = 42;

  bool _showLyrics = false;
  bool _favorite = false;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveFavorite());
  }

  @override
  void didUpdateWidget(covariant _MusicoletNowPlaying oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.sourceTrackId != widget.track.sourceTrackId ||
        oldWidget.track.id != widget.track.id) {
      unawaited(_resolveFavorite());
    }
  }

  /// Heart state = membership of the REAL "Favorites" playlist.
  Future<void> _resolveFavorite() async {
    final track = widget.track;
    if (track.id == null) {
      return;
    }
    try {
      final dao = ref.read(databaseProvider).playlistsDao;
      final id = await _favoritesPlaylistId();
      if (id == null) {
        return;
      }
      final tracks = await dao.tracksOf(id);
      final found = tracks.any((t) => t.id == track.id);
      if (!mounted || widget.track.id != track.id) {
        return;
      }
      setState(() {
        _favorite = found;
      });
    } on Object {
      // Database unavailable (tests / web) — the heart still toggles
      // optimistically.
    }
  }

  Future<int?> _favoritesPlaylistId() async {
    final dao = ref.read(databaseProvider).playlistsDao;
    final playlists = await dao.getAll();
    for (final playlist in playlists) {
      if (playlist.name.toLowerCase() == 'favorites') {
        return playlist.id;
      }
    }
    return dao.createPlaylist('Favorites');
  }

  Future<void> _toggleFavorite() async {
    final track = widget.track;
    if (track.id == null) {
      return;
    }
    final next = !_favorite;
    setState(() => _favorite = next);
    try {
      final dao = ref.read(databaseProvider).playlistsDao;
      final id = await _favoritesPlaylistId();
      if (id == null) {
        return;
      }
      if (next) {
        await dao.addTracks(id, <int>[track.id!]);
      } else {
        await dao.removeTrack(id, track.id!);
      }
    } on Object {
      if (mounted) {
        setState(() => _favorite = !next);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(queueManagerProvider.notifier);
    final queue = ref.watch(queueManagerProvider);
    final track = widget.track;
    final isPlaying = queue.playbackState == PlaybackState.playing;
    final coverSize = AppConstants.nowPlayingCoverSizeMobile;
    final minTarget = BoxConstraints(
      minWidth: AppConstants.touchTargetMin,
      minHeight: AppConstants.touchTargetMin,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            children: <Widget>[
              // -- top row: back + options --------------------------------
              Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    color: Colors.white,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Sleep timer',
                    onPressed: () =>
                        unawaited(showSleepTimerDialog(context, ref)),
                    color: queue.sleepTimerEndsAt != null
                        ? MusicoletColors.green
                        : Colors.white,
                    icon: const Icon(Icons.timer_outlined),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: WavelyDurations.normal,
                    child: _showLyrics
                        ? LyricsView(
                            key: const ValueKey<String>('lyrics-view'),
                            track: track,
                            positionStream: ref
                                .read(playbackEngineProvider)
                                .positionStream,
                            onSeek: manager.seek,
                            height: coverSize,
                          )
                        : GestureDetector(
                            key: const ValueKey<String>('now-playing-cover'),
                            onTap: () =>
                                setState(() => _showLyrics = !_showLyrics),
                            child: Container(
                              width: coverSize,
                              height: coverSize,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: MusicoletColors.sheetCard,
                              ),
                              child: WavelyCover(
                                label: track.title,
                                coverPath: track.coverPath,
                                borderRadius: BorderRadius.zero,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: WavelyTypography.title20(color: Colors.white),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                track.artistOrUnknown,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: WavelyTypography.body14(color: Colors.white70),
              ),
              if (track.album?.isNotEmpty == true) ...<Widget>[
                const SizedBox(height: Spacing.xs),
                Text(
                  track.album!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: WavelyTypography.caption12(color: Colors.white54),
                ),
              ],
              const SizedBox(height: Spacing.md),
              // -- icon row: Heart · Info · Add to queue · 3-dots ---------
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  IconButton(
                    constraints: minTarget,
                    tooltip: 'Favorite',
                    onPressed: () => unawaited(_toggleFavorite()),
                    color: _favorite
                        ? MusicoletColors.green
                        : Colors.white,
                    icon: Icon(
                      _favorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                    ),
                  ),
                  IconButton(
                    constraints: minTarget,
                    tooltip: 'Song info',
                    onPressed: () => unawaited(
                      showTrackInfoDialog(context, track),
                    ),
                    color: Colors.white,
                    icon: const Icon(Icons.info_outline_rounded),
                  ),
                  IconButton(
                    constraints: minTarget,
                    tooltip: 'Add to queue',
                    onPressed: () {
                      unawaited(
                        ref
                            .read(queueManagerProvider.notifier)
                            .appendToQueue(<Track>[track]),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: MusicoletColors.greenDark,
                          content: Text(
                            'Added to the queue',
                            style: WavelyTypography.body14(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      );
                    },
                    color: Colors.white,
                    icon: const Icon(Icons.playlist_add_rounded),
                  ),
                  IconButton(
                    constraints: minTarget,
                    tooltip: 'More options',
                    onPressed: () => unawaited(
                      showSongOptionsSheet(context, ref, track),
                    ),
                    color: Colors.white,
                    icon: const Icon(Icons.more_vert_rounded),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              _buildSeekbarRow(context.wavelyColors, manager, queue),
              _buildControls(manager, queue, isPlaying),
            ],
          ),
        ),
      ),
    );
  }

  /// Musicolet parity: shuffle and repeat flank the seekbar.
  Widget _buildSeekbarRow(
    WavelySemanticColors colors,
    QueueManager manager,
    QueueState queue,
  ) {
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: 'Shuffle',
          onPressed: () => unawaited(manager.toggleShuffle()),
          color: queue.shuffleEnabled
              ? MusicoletColors.green
              : Colors.white70,
          icon: const Icon(Icons.shuffle_rounded),
        ),
        Expanded(child: _buildSeekbar(queue)),
        IconButton(
          tooltip: 'Repeat',
          onPressed: () => manager.setRepeatMode(
            switch (queue.repeatMode) {
              RepeatMode.off => RepeatMode.all,
              RepeatMode.all => RepeatMode.one,
              RepeatMode.one => RepeatMode.off,
            },
          ),
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
    );
  }

  Widget _buildSeekbar(QueueState queue) {
    final durationMs = queue.duration.inMilliseconds;
    final positionMs = queue.position.inMilliseconds;
    final value = durationMs <= 0
        ? 0.0
        : (positionMs / durationMs).clamp(0.0, 1.0).toDouble();
    return Semantics(
      label: 'Seek',
      child: Row(
        children: <Widget>[
          Text(
            queue.position.hm,
            style: WavelyTypography.timerTabular(
              color: Colors.white70,
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              activeColor: MusicoletColors.green,
              inactiveColor: MusicoletColors.divider,
              onChanged: durationMs <= 0
                  ? null
                  : (v) => unawaited(
                        ref
                            .read(queueManagerProvider.notifier)
                            .seek(
                              Duration(
                                milliseconds: (v * durationMs).round(),
                              ),
                            ),
                      ),
            ),
          ),
          Text(
            queue.duration.hm,
            style: WavelyTypography.timerTabular(
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  /// Musicolet transport row: Rewind · Prev · Play · Next · FF · EQ.
  Widget _buildControls(
    QueueManager manager,
    QueueState queue,
    bool isPlaying,
  ) {
    final minTarget = BoxConstraints(
      minWidth: AppConstants.touchTargetMin,
      minHeight: AppConstants.touchTargetMin,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Semantics(
          label: 'Rewind 10 seconds',
          button: true,
          child: IconButton(
            constraints: minTarget,
            tooltip: 'Rewind',
            onPressed: () => unawaited(
              manager.seek(
                (queue.position - const Duration(seconds: 10)) <
                        Duration.zero
                    ? Duration.zero
                    : queue.position - const Duration(seconds: 10),
              ),
            ),
            color: Colors.white,
            icon: const Icon(Icons.replay_10_rounded),
          ),
        ),
        Semantics(
          label: 'Previous track',
          button: true,
          child: IconButton(
            constraints: minTarget,
            tooltip: 'Previous',
            onPressed: () => unawaited(manager.previous()),
            color: Colors.white,
            iconSize: _skipIconSize,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
        ),
        Semantics(
          label: isPlaying ? 'Pause' : 'Play',
          button: true,
          child: IconButton(
            constraints: minTarget,
            tooltip: 'Play or pause',
            onPressed: () => unawaited(manager.togglePlayPause()),
            color: MusicoletColors.green,
            iconSize: _playButtonSize,
            icon: Icon(
              isPlaying
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
            ),
          ),
        ),
        Semantics(
          label: 'Next track',
          button: true,
          child: IconButton(
            constraints: minTarget,
            tooltip: 'Next',
            onPressed: () => unawaited(manager.next()),
            color: Colors.white,
            iconSize: _skipIconSize,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ),
        Semantics(
          label: 'Forward 10 seconds',
          button: true,
          child: IconButton(
            constraints: minTarget,
            tooltip: 'Forward',
            onPressed: () => unawaited(
              manager.seek(
                queue.position + const Duration(seconds: 10),
              ),
            ),
            color: Colors.white,
            icon: const Icon(Icons.forward_10_rounded),
          ),
        ),
        Semantics(
          label: 'Equalizer',
          button: true,
          child: IconButton(
            constraints: minTarget,
            tooltip: 'Equalizer',
            onPressed: () => unawaited(context.push(kEqualizerRoute)),
            color: Colors.white,
            icon: const Icon(Icons.equalizer_rounded),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared secondary sheet (kept from v1.0.1: speed picker is used by the
// song options sheet on mobile and by the desktop body inline).
// ---------------------------------------------------------------------------

/// Opens the classic queue list sheet (swipe-to-remove).
Future<void> showQueueListSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => QueueSheet(
      onClose: () => Navigator.of(sheetContext).pop(),
    ),
  );
}

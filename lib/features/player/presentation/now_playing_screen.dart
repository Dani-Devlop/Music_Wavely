import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/extensions/extensions.dart';
import 'package:wavely/core/utils/platform_utils.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/presentation/local_cover.dart';
import 'package:wavely/features/lyrics/presentation/lyrics_view.dart';
import 'package:wavely/features/player/presentation/queue_sheet.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

/// Full-screen now-playing view: blurred cover backdrop, seek slider,
/// transport controls, speed + sleep-timer row and a tappable lyrics
/// overlay.
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
  /// Speed menu choices (engine rate API lands post-1.1; see QueueManager).
  static const List<double> _speedOptions = <double>[
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];
  static const double _playButtonSize = 72;
  static const double _skipIconSize = 40;
  static const double _backdropScrimOpacity = 0.5;
  static const double _fallbackCoverIconSize = 64;

  bool _showLyrics = false;

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(queueManagerProvider.notifier);
    final queue = ref.watch(queueManagerProvider);
    final engine = ref.watch(playbackEngineProvider);
    final colors = context.wavelyColors;
    final track = queue.currentTrack;
    if (track == null) {
      return Scaffold(
        backgroundColor: colors.bgBase,
        body: const Center(
          child: EmptyState(icon: Icons.music_off, title: 'Nothing playing'),
        ),
      );
    }
    final coverSize = PlatformUtils.isDesktop
        ? AppConstants.nowPlayingCoverSizeDesktop
        : AppConstants.nowPlayingCoverSizeMobile;
    final isPlaying = queue.playbackState == PlaybackState.playing;
    return Scaffold(
      backgroundColor: colors.bgBase,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _buildBackdrop(colors, track),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.xl),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: WavelyDurations.normal,
                        child: _showLyrics
                            ? LyricsView(
                                key: const ValueKey<String>('lyrics-view'),
                                track: track,
                                positionStream: engine.positionStream,
                                onSeek: manager.seek,
                                height: coverSize,
                              )
                            : _buildCover(colors, track, coverSize),
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: WavelyTypography.title20(color: colors.textPrimary),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    track.artistOrUnknown,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style:
                        WavelyTypography.body14(color: colors.textSecondary),
                  ),
                  const SizedBox(height: Spacing.lg),
                  _buildSeekbar(colors, manager, queue),
                  _buildControls(colors, manager, queue, isPlaying),
                  _buildSecondaryRow(colors, manager, queue),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -- backdrop -------------------------------------------------------------

  Widget _buildBackdrop(WavelySemanticColors colors, Track track) {
    final cover = track.coverPath;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _coverImage(
          cover,
          fallback: _gradientFallback(colors),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: WavelyBlur.elevated,
              sigmaY: WavelyBlur.elevated,
            ),
            child: ColoredBox(
              color: colors.bgBase.withValues(alpha: _backdropScrimOpacity),
            ),
          ),
        ),
      ],
    );
  }

  Widget _gradientFallback(WavelySemanticColors colors) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              colors.accentColors.gradientStart,
              colors.bgBase,
            ],
          ),
        ),
      );

  Widget _buildCover(
    WavelySemanticColors colors,
    Track track,
    double size,
  ) {
    final cover = track.coverPath;
    return Semantics(
      button: true,
      label: 'Show lyrics',
      child: GestureDetector(
        key: const ValueKey<String>('now-playing-cover'),
        onTap: () => setState(() => _showLyrics = !_showLyrics),
        child: Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: AppRadii.bXl,
            color: colors.elevated,
            boxShadow: WavelyShadows.dark,
          ),
          child: _coverImage(
            cover,
            fallback: _coverFallback(colors),
          ),
        ),
      ),
    );
  }

  /// Local-file cover image. On web (and for missing files) the conditional
  /// `local_cover` import resolves to no provider, so the fallback renders
  /// instead — this file must stay free of `dart:io` to compile on web.
  Widget _coverImage(
    String? cover, {
    required Widget fallback,
  }) {
    final provider =
        cover == null || cover.isEmpty ? null : localCoverProvider(cover);
    if (provider == null) {
      return fallback;
    }
    return Image(
      image: provider,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  Widget _coverFallback(WavelySemanticColors colors) => Center(
        child: Icon(
          Icons.music_note,
          size: _fallbackCoverIconSize,
          color: colors.textTertiary,
        ),
      );

  // -- seekbar + controls ---------------------------------------------------

  Widget _buildSeekbar(
    WavelySemanticColors colors,
    QueueManager manager,
    QueueState queue,
  ) {
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
              color: colors.textSecondary,
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              onChanged: durationMs <= 0
                  ? null
                  : (v) => unawaited(
                        manager.seek(
                          Duration(milliseconds: (v * durationMs).round()),
                        ),
                      ),
            ),
          ),
          Text(
            queue.duration.hm,
            style: WavelyTypography.timerTabular(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(
    WavelySemanticColors colors,
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
          label: 'Shuffle',
          button: true,
          child: IconButton(
            constraints: minTarget,
            tooltip: 'Shuffle',
            onPressed: () => unawaited(manager.toggleShuffle()),
            color: queue.shuffleEnabled
                ? colors.accentColors.accent
                : colors.textPrimary,
            icon: const Icon(Icons.shuffle),
          ),
        ),
        Semantics(
          label: 'Previous track',
          button: true,
          child: IconButton(
            constraints: minTarget,
            tooltip: 'Previous',
            onPressed: () => unawaited(manager.previous()),
            color: colors.textPrimary,
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
            color: colors.textPrimary,
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
            color: colors.textPrimary,
            iconSize: _skipIconSize,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ),
        Semantics(
          label: 'Repeat mode',
          button: true,
          child: IconButton(
            constraints: minTarget,
            tooltip: 'Repeat',
            onPressed: () => manager.setRepeatMode(
              switch (queue.repeatMode) {
                RepeatMode.off => RepeatMode.all,
                RepeatMode.all => RepeatMode.one,
                RepeatMode.one => RepeatMode.off,
              },
            ),
            color: queue.repeatMode == RepeatMode.off
                ? colors.textPrimary
                : colors.accentColors.accent,
            icon: Icon(
              queue.repeatMode == RepeatMode.one
                  ? Icons.repeat_one
                  : Icons.repeat,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSecondaryRow(
    WavelySemanticColors colors,
    QueueManager manager,
    QueueState queue,
  ) {
    final endsAt = queue.sleepTimerEndsAt;
    final minTarget = BoxConstraints(
      minWidth: AppConstants.touchTargetMin,
      minHeight: AppConstants.touchTargetMin,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Semantics(
          label: 'Queue',
          button: true,
          child: IconButton(
            constraints: minTarget,
            tooltip: 'Queue',
            onPressed: () => unawaited(_showQueueSheet()),
            color: colors.textPrimary,
            icon: const Icon(Icons.queue_music_rounded),
          ),
        ),
        PopupMenuButton<double>(
          initialValue:
              _speedOptions.contains(queue.speed) ? queue.speed : null,
          tooltip: 'Playback speed',
          onSelected: manager.setSpeed,
          itemBuilder: (context) => <PopupMenuEntry<double>>[
            for (final speed in _speedOptions)
              PopupMenuItem<double>(
                value: speed,
                child: Text('${speed}x'),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.all(Spacing.sm),
            child: Text(
              '${queue.speed}x',
              style: WavelyTypography.body14Medium(
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
        if (endsAt != null)
          Text(
            _remainingLabel(endsAt),
            style: WavelyTypography.micro10(color: colors.textTertiary),
          ),
        Semantics(
          label: 'Sleep timer',
          button: true,
          child: IconButton(
            constraints: minTarget,
            tooltip: 'Sleep timer',
            onPressed: () => unawaited(_showSleepSheet(manager)),
            color: endsAt != null
                ? colors.accentColors.accent
                : colors.textPrimary,
            icon: const Icon(Icons.timer_outlined),
          ),
        ),
      ],
    );
  }

  String _remainingLabel(DateTime endsAt) {
    final remaining = endsAt.difference(DateTime.now());
    return remaining.inSeconds <= 0 ? '0:00' : remaining.hm;
  }

  /// Hosts the queue sheet (Task 4/E5 wiring; the sheet content is owned by
  /// queue_sheet.dart and designed for this caller).
  Future<void> _showQueueSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => QueueSheet(
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    );
  }

  Future<void> _showSleepSheet(QueueManager manager) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final minutes in AppConstants.sleepTimerPresetsMinutes)
              ListTile(
                title: Text('$minutes min'),
                onTap: () {
                  manager.startSleepTimer(Duration(minutes: minutes));
                  Navigator.of(sheetContext).pop();
                },
              ),
            ListTile(
              title: const Text('Off'),
              onTap: () {
                manager.cancelSleepTimer();
                Navigator.of(sheetContext).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

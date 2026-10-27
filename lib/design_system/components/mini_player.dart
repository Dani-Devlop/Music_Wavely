import 'package:flutter/material.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/design_system/components/glass_card.dart';
import 'package:wavely/design_system/components/track_tile.dart';
import 'package:wavely/design_system/components/wavely_cover.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/design_system/tokens/radii.dart';
import 'package:wavely/design_system/tokens/spacing.dart';
import 'package:wavely/design_system/tokens/typography.dart';
import 'package:wavely/domain/entities/entities.dart';

/// Compact persistent player bar.
///
/// Glass surface (elevated) with cover, title/artist or a "Nothing playing"
/// empty state, play/pause (+ optional next) controls with 44dp+ padded
/// targets, a hairline progress strip pinned to the bottom edge, and a
/// whole-tile tap that opens the now-playing screen.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    required this.track,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.onPlayPause,
    required this.onTap,
    this.onNext,
    super.key,
  });

  final Track? track;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final VoidCallback onPlayPause;
  final VoidCallback onTap;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final current = track;
    return GlassCard(
      elevated: true,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: AppConstants.trackTileCoverSize,
                  height: AppConstants.trackTileCoverSize,
                  child: ClipRRect(
                    borderRadius: AppRadii.bSm,
                    child: _cover(current),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: current == null
                      ? Text(
                          'Nothing playing',
                          style: WavelyTypography.body14Medium(
                            color: colors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              current.title,
                              style: WavelyTypography.body14Medium(
                                color: colors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              current.artistOrUnknown,
                              style: WavelyTypography.caption12(
                                color: colors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                ),
                IconButton(
                  onPressed: onPlayPause,
                  tooltip: isPlaying ? 'Pause' : 'Play',
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                if (onNext != null)
                  IconButton(
                    onPressed: onNext,
                    tooltip: 'Next',
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
              ],
            ),
          ),
          _MiniProgressBar(position: position, duration: duration),
        ],
      ),
    );
  }

  Widget _cover(Track? current) {
    final fallback = WavelyCoverFallback(label: current?.title ?? '');
    final provider = wavelyCoverProvider(current?.coverPath);
    if (provider != null) {
      return Image(
        image: provider,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return fallback;
  }
}

/// Hairline playback progress strip at the bottom of [MiniPlayer].
class _MiniProgressBar extends StatelessWidget {
  const _MiniProgressBar({required this.position, required this.duration});

  /// Strip height in logical pixels (no matching spacing token for a
  /// 2dp hairline).
  static const double barHeight = 2;

  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final totalMs = duration.inMilliseconds;
    final double fraction;
    if (totalMs <= 0) {
      fraction = 0;
    } else {
      final raw = position.inMilliseconds / totalMs;
      fraction = raw < 0 ? 0 : (raw > 1 ? 1 : raw);
    }
    return LinearProgressIndicator(
      value: fraction,
      minHeight: _MiniProgressBar.barHeight,
      backgroundColor: colors.borderGlass,
      color: colors.accentColors.accent,
      semanticsLabel: 'Playback progress',
    );
  }
}

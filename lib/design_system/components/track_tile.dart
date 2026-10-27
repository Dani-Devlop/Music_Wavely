import 'package:flutter/material.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/extensions/extensions.dart';
import 'package:wavely/design_system/components/explicit_badge.dart';
import 'package:wavely/design_system/components/source_badge.dart';
import 'package:wavely/design_system/components/wavely_cover.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/design_system/tokens/radii.dart';
import 'package:wavely/design_system/tokens/spacing.dart';
import 'package:wavely/design_system/tokens/typography.dart';
import 'package:wavely/domain/entities/entities.dart';

/// Accent-gradient fallback for missing or unloadable cover art.
///
/// Fills its parent (wrap it in a sized box / aspect ratio / clip shape) and
/// renders the first character of [label]; a blank label shows a note glyph.
/// Shared by every cover-bearing component (tiles, cards, circles, player).
class WavelyCoverFallback extends StatelessWidget {
  const WavelyCoverFallback({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final trimmed = label.trim();
    final initial = trimmed.isBlank ? '♪' : trimmed[0].toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colors.accentColors.gradientStart,
            colors.accentColors.accent,
          ],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: WavelyTypography.body14Medium(color: colors.textPrimary),
        ),
      ),
    );
  }
}

/// A single row in the track list.
///
/// Pure presentation: cover (file image with a [WavelyCoverFallback]
/// error fallback), title/artist, duration, optional explicit and source
/// badges and an optional trailing slot. The whole row is the tap target
/// (minimum height AppConstants.touchTargetMin) and exposes merged
/// semantics for screen readers.
class TrackTile extends StatelessWidget {
  const TrackTile({
    required this.track,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.selected = false,
    this.showSourceBadge = false,
    super.key,
  });

  static const String _selectedKey = 'wavely.trackTile.selected';
  static const String _semanticsKey = 'wavely.trackTile.semantics';

  final Track track;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final bool selected;
  final bool showSourceBadge;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final coverSize = AppConstants.trackTileCoverSize;
    return MergeSemantics(
      key: const ValueKey<String>(_semanticsKey),
      child: Semantics(
        label:
            '${track.title} by ${track.artistOrUnknown}, '
            'duration ${track.displayDuration}',
        onTapHint: 'Play',
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: AppRadii.bMd,
          child: Container(
            key: selected ? const ValueKey<String>(_selectedKey) : null,
            constraints:
                const BoxConstraints(minHeight: AppConstants.touchTargetMin),
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm,
              vertical: Spacing.xs,
            ),
            decoration: selected
                ? BoxDecoration(
                    color:
                        colors.accentColors.accent.withValues(alpha: 0.12),
                    borderRadius: AppRadii.bMd,
                    border:
                        Border.all(color: colors.accentColors.accent),
                  )
                : null,
            child: Row(
              children: [
                SizedBox(
                  width: coverSize,
                  height: coverSize,
                  child: ClipRRect(
                    borderRadius: AppRadii.bSm,
                    child: _cover(),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        style: WavelyTypography.body14Medium(
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        track.artistOrUnknown,
                        style: WavelyTypography.caption12(
                          color: colors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (track.explicit) ...[
                  const SizedBox(width: Spacing.sm),
                  const ExplicitBadge(),
                ],
                if (showSourceBadge) ...[
                  const SizedBox(width: Spacing.sm),
                  SourceBadge(sourceId: track.sourceId),
                ],
                const SizedBox(width: Spacing.sm),
                Text(
                  track.displayDuration,
                  style: WavelyTypography.timerTabular(
                    color: colors.textTertiary,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: Spacing.sm),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover() {
    final provider = wavelyCoverProvider(track.coverPath);
    if (provider != null) {
      return Image(
        image: provider,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => WavelyCoverFallback(label: track.title),
      );
    }
    return WavelyCoverFallback(label: track.title);
  }
}

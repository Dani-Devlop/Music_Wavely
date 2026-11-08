import 'package:flutter/material.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/design_system/components/explicit_badge.dart';
import 'package:wavely/design_system/components/source_badge.dart';
import 'package:wavely/design_system/components/wavely_cover.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/design_system/tokens/radii.dart';
import 'package:wavely/design_system/tokens/spacing.dart';
import 'package:wavely/design_system/tokens/typography.dart';
import 'package:wavely/domain/entities/entities.dart';

/// Premium auto-generated fallback for missing or unloadable cover art.
///
/// v1.0.1-beta3 (owner spec): NEVER a letter tile. Instead a beautiful
/// duotone gradient **derived from a stable FNV-1a hash of [label]** (the
/// track/album/artist name), with a glowing white music-note glyph on top
/// plus a soft diagonal sheen so every cover-less item still looks
/// designed. Shared by every cover-bearing component (tiles, cards,
/// circles, player).
class WavelyCoverFallback extends StatelessWidget {
  const WavelyCoverFallback({required this.label, super.key});

  final String label;

  /// Stable 32-bit FNV-1a over UTF-16 code units: deterministic across
  /// platforms, isolates, hot-restarts and SDK upgrades (unlike
  /// [String.hashCode], which is only stable within one VM).
  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < value.length; i++) {
      hash ^= value.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  @override
  Widget build(BuildContext context) {
    final palette =
        _fallbackPalettes[_stableHash(label) % _fallbackPalettes.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // Soft diagonal sheen: makes the flat duotone read as "glassy
          // artwork" rather than a flat color block.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: <double>[0, 0.55, 1],
                colors: <Color>[
                  Color(0x33FFFFFF),
                  Color(0x00000000),
                  Color(0x1A000000),
                ],
              ),
            ),
            child: SizedBox.expand(),
          ),
          // Premium glowing white note glyph — the signature of a
          // cover-less Wavely item (owner spec: never a letter). Scales
          // with the cover size (rows, cards, hero art).
          LayoutBuilder(
            builder: (context, constraints) {
              final widest = constraints.maxWidth;
              final size = widest.isFinite
                  ? (widest * 0.34).clamp(15.0, 44.0)
                  : 22.0;
              return Icon(
                Icons.music_note_rounded,
                size: size,
                color: Colors.white.withValues(alpha: 0.95),
                shadows: const <Shadow>[
                  Shadow(
                    color: Color(0xAA000000),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                  Shadow(
                    color: Color(0x59FFFFFF),
                    blurRadius: 14,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Curated duotone gradient pairs for [WavelyCoverFallback] — deep, rich,
/// artwork-grade colors (the fallback must feel designed, not placeholder).
const List<List<Color>> _fallbackPalettes = <List<Color>>[
  <Color>[Color(0xFF6D28D9), Color(0xFFC026D3)], // violet → fuchsia
  <Color>[Color(0xFF0F766E), Color(0xFF2DD4BF)], // deep teal
  <Color>[Color(0xFFB45309), Color(0xFFFBBF24)], // amber
  <Color>[Color(0xFFBE123C), Color(0xFFFB7185)], // rose
  <Color>[Color(0xFF166534), Color(0xFF4ADE80)], // forest green
  <Color>[Color(0xFF7C2D12), Color(0xFFFB923C)], // burnt orange
  <Color>[Color(0xFF4C1D95), Color(0xFFA78BFA)], // royal violet
  <Color>[Color(0xFF0C4A6E), Color(0xFF38BDF8)], // deep sky
  <Color>[Color(0xFF701A75), Color(0xFFE879F9)], // magenta
  <Color>[Color(0xFF713F12), Color(0xFFEAB308)], // gold
  <Color>[Color(0xFF134E4A), Color(0xFF5EEAD4)], // aqua
  <Color>[Color(0xFF3F3F46), Color(0xFFA1A1AA)], // graphite
];

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
    const coverSize = AppConstants.trackTileCoverSize;
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

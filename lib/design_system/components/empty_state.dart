import 'package:flutter/material.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/design_system/tokens/radii.dart';
import 'package:wavely/design_system/tokens/spacing.dart';
import 'package:wavely/design_system/tokens/typography.dart';

/// Fixed metrics of the empty-state illustration.
const double _outerRing = 148;
const double _innerRing = 116;
const double _badgeDiameter = 88;
const double _iconSize = 40;

/// Centered empty-state placeholder with an optional glowing CTA.
///
/// The 2026 overhaul replaces the old single-circle placeholder with a
/// layered ring illustration (two concentric accent rings around a glowing
/// badge), display-scale typography and a CTA that carries a soft accent
/// glow. The public API is unchanged: the CTA renders only when BOTH
/// [ctaLabel] and [onCta] are provided.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
    this.ctaLabel,
    this.onCta,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final accent = colors.accentColors.accent;
    final showCta = ctaLabel != null && onCta != null;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _outerRing,
            height: _outerRing,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer breathing ring.
                Container(
                  width: _outerRing,
                  height: _outerRing,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(alpha: 0.10),
                      width: 1.5,
                    ),
                  ),
                ),
                Container(
                  width: _innerRing,
                  height: _innerRing,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(alpha: 0.22),
                      width: 1.5,
                    ),
                  ),
                ),
                Container(
                  width: _badgeDiameter,
                  height: _badgeDiameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.14),
                    border: Border.all(color: accent.withValues(alpha: 0.45)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: accent.withValues(alpha: 0.28),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: _iconSize, color: accent),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.xl),
          Text(
            title,
            style: WavelyTypography.display24(color: colors.textPrimary),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              subtitle!,
              style: WavelyTypography.body14(color: colors.textSecondary),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (showCta) ...[
            const SizedBox(height: Spacing.xl),
            // The glow lives OUTSIDE the button so the pressed/hover states
            // of the button itself stay untouched.
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(alpha: 0.40),
                    blurRadius: 26,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppConstants.touchTargetMin,
                ),
                child: FilledButton(
                  onPressed: onCta,
                  child: Text(ctaLabel!),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

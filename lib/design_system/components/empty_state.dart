import 'package:flutter/material.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/design_system/tokens/spacing.dart';
import 'package:wavely/design_system/tokens/typography.dart';

/// Fixed metrics of the empty-state illustration (no matching tokens).
const double _circleDiameter = 64;
const double _iconSize = 32;

/// Centered empty-state placeholder with optional CTA.
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
    final showCta = ctaLabel != null && onCta != null;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _circleDiameter,
            height: _circleDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.accentColors.accent.withValues(alpha: 0.12),
              border: Border.all(color: colors.borderGlass),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: _iconSize,
              color: colors.accentColors.accent,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            title,
            style: WavelyTypography.title20(color: colors.textPrimary),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              subtitle!,
              style: WavelyTypography.caption12(color: colors.textSecondary),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (showCta) ...[
            const SizedBox(height: Spacing.lg),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppConstants.touchTargetMin,
              ),
              child: FilledButton(
                onPressed: onCta,
                child: Text(ctaLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

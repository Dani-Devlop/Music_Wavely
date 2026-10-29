import 'package:flutter/material.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/design_system/tokens/durations.dart';
import 'package:wavely/design_system/tokens/radii.dart';
import 'package:wavely/design_system/tokens/spacing.dart';
import 'package:wavely/design_system/tokens/typography.dart';

/// Icon glyph size inside the chip (fixed brand metric, no token).
const double _chipIconSize = 16;

/// Custom filter chip (single-select style used across library screens).
///
/// Selected: accent background (18% alpha), accent border and accent text.
/// Unselected: transparent background, glass border, secondary text.
/// The visual pill is ~32dp tall and is vertically centered inside an exact
/// AppConstants.touchTargetMin tap area (ConstrainedBox + Align with
/// heightFactor 1 keeps sizing deterministic under any parent constraints).
class ChipFilter extends StatelessWidget {
  const ChipFilter({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    super.key,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final IconData? icon;

  static const String _semanticsKey = 'wavely.chipFilter.semantics';

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final accent = colors.accentColors.accent;
    return Semantics(
      key: const ValueKey<String>(_semanticsKey),
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: () => onSelected(!selected),
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppConstants.touchTargetMin,
          ),
          child: Align(
            alignment: Alignment.center,
            heightFactor: 1,
            child: AnimatedContainer(
              duration: WavelyDurations.fast,
              curve: WavelyDurations.standard,
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              decoration: BoxDecoration(
                color:
                    selected ? accent.withValues(alpha: 0.18) : Colors.transparent,
                borderRadius: AppRadii.bPill,
                border:
                    Border.all(color: selected ? accent : colors.borderGlass),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: _chipIconSize,
                      color: selected ? accent : colors.textSecondary,
                    ),
                    const SizedBox(width: Spacing.xs),
                  ],
                  Text(
                    label,
                    style: WavelyTypography.body14Medium(
                      color: selected ? accent : colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

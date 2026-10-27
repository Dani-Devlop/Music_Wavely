import 'package:flutter/material.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/design_system/tokens/spacing.dart';
import 'package:wavely/design_system/tokens/typography.dart';

/// List/section title row with an optional trailing action.
///
/// The action (label + callback) renders only when both are provided; the
/// row keeps a minimum height of AppConstants.touchTargetMin and the action
/// button uses the theme's padded tap target (>= 44dp).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.actionLabel = 'See all',
    this.onAction,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final showAction = actionLabel != null && onAction != null;
    return Container(
      constraints:
          const BoxConstraints(minHeight: AppConstants.touchTargetMin),
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: WavelyTypography.title18(color: colors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showAction)
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: WavelyTypography.body14Medium(
                  color: colors.accentColors.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

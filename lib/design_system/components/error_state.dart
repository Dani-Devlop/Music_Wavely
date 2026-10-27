import 'package:flutter/material.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/design_system/tokens/spacing.dart';
import 'package:wavely/design_system/tokens/typography.dart';

/// Fixed metrics of the error-state illustration (no matching tokens).
const double _circleDiameter = 64;
const double _iconSize = 32;

/// Centered error-state placeholder with a mandatory retry action.
class ErrorState extends StatelessWidget {
  const ErrorState({
    required this.message,
    this.detail,
    required this.onRetry,
    super.key,
  });

  final String message;
  final String? detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _circleDiameter,
            height: _circleDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.error.withValues(alpha: 0.12),
              border: Border.all(color: colors.borderGlass),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.error_outline_rounded,
              size: _iconSize,
              color: colors.error,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            message,
            style: WavelyTypography.title20(color: colors.textPrimary),
            textAlign: TextAlign.center,
          ),
          if (detail != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              detail!,
              style: WavelyTypography.caption12(color: colors.textSecondary),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: Spacing.lg),
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppConstants.touchTargetMin,
            ),
            child: OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ),
        ],
      ),
    );
  }
}

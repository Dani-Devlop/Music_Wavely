import 'package:flutter/material.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/design_system/tokens/typography.dart';

/// Corner radius of the badge (fixed brand mark, no matching token).
const double _badgeCornerRadius = 4;

/// Semantics node key used by tests to resolve the merged node.
const String _semanticsKey = 'wavely.explicitBadge.semantics';

/// "E" mark for explicit tracks (Apple-style parental-advisory hint).
class ExplicitBadge extends StatelessWidget {
  const ExplicitBadge({this.size = 16, super.key});

  /// Side length of the square badge in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return MergeSemantics(
      key: const ValueKey<String>(_semanticsKey),
      child: Semantics(
        label: 'Explicit',
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: colors.textTertiary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(_badgeCornerRadius),
          ),
          alignment: Alignment.center,
          child: Text(
            'E',
            style: WavelyTypography.micro10(color: colors.textPrimary)
                .copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

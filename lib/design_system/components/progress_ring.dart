import 'package:flutter/material.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';

/// Small circular progress indicator.
///
/// [value] in 0..1 renders a determinate ring (clamped); leave it null for
/// an indeterminate spinner. Size and stroke can be tuned per call site.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    this.value,
    this.size = 36,
    this.strokeWidth = 3,
    this.color,
    super.key,
  });

  /// Progress in 0..1, or null for an indeterminate spinner.
  final double? value;

  /// Outer diameter in logical pixels.
  final double size;

  /// Ring stroke width in logical pixels.
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Semantics(
      label: 'Loading',
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          value: value?.clamp(0, 1).toDouble(),
          strokeWidth: strokeWidth,
          color: color ?? colors.accentColors.accent,
        ),
      ),
    );
  }
}

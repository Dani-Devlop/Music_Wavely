import 'package:flutter/material.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/design_system/tokens/radii.dart';

/// Sweep period of the shimmer highlight.
///
/// Private constant instead of an AppConstants entry: the period is a purely
/// local presentation detail (1200 ms reads as a slow shimmer without being
/// distracting) and AppConstants is outside the components' scope.
abstract final class _ShimmerTiming {
  static const int periodMs = 1200;
}

/// Opacity of the specular highlight band (theme-independent by design).
const double _shimmerHighlightAlpha = 0.08;

/// Shimmer sweep overlay for loading placeholders.
///
/// Animates a soft highlight band across [child]. Intentionally EXCLUDED
/// from golden captures: the repeating controller never settles, so
/// captures would be timing-dependent.
class Shimmer extends StatefulWidget {
  const Shimmer({required this.child, super.key});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _ShimmerTiming.periodMs),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) => _sweep.createShader(bounds),
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
    );
  }

  LinearGradient get _sweep {
    final shift = _controller.value * 4 - 2;
    return LinearGradient(
      begin: Alignment(shift - 1, -1),
      end: Alignment(shift + 1, 1),
      colors: <Color>[
        Colors.transparent,
        Colors.white.withValues(alpha: _shimmerHighlightAlpha),
        Colors.transparent,
      ],
    );
  }
}

/// Skeleton box convenience: a rounded translucent placeholder wrapped in
/// [Shimmer]. Sizes to [width] x [height] when given, else to its parent.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({this.width, this.height, this.radius, super.key});

  final double? width;
  final double? height;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Shimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: colors.textTertiary.withValues(alpha: 0.15),
          borderRadius: radius ?? AppRadii.bSm,
        ),
      ),
    );
  }
}

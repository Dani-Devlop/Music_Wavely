import 'package:flutter/material.dart';

/// Per-item delay between staggered entries (40ms — fast enough to feel
/// like one wave, slow enough to read as a cascade).
const Duration _staggerStep = Duration(milliseconds: 40);

/// Base fade/slide duration once an item's delay has elapsed.
const Duration _staggerBase = Duration(milliseconds: 240);

/// Implicit staggered entrance: fades and slides [child] in with a delay
/// derived from [index] (index 0 starts immediately, each next item 40ms
/// later). Runs once per widget lifetime — the tween never changes, so
/// parent rebuilds (scan progress, list updates) do NOT replay the
/// animation.
///
/// A zero-dependency alternative to `flutter_animate`, sized for list/grid
/// stagger effects; [StaggeredAppear] adds no opacity layer after it
/// finishes (the builder converges to opacity 1 / offset 0).
class StaggeredAppear extends StatelessWidget {
  /// Creates the entrance wrapper; [index] positions the item in the
  /// stagger wave (0-based).
  const StaggeredAppear({
    required this.child,
    this.index = 0,
    super.key,
  });

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    final delayMs = index * _staggerStep.inMilliseconds;
    final totalMs = _staggerBase.inMilliseconds + delayMs;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      curve: Interval(
        totalMs == 0 ? 0 : delayMs / totalMs,
        1,
        curve: Curves.easeOutCubic,
      ),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 12),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

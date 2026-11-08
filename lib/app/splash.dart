import 'package:flutter/material.dart';
import 'package:wavely/design_system/components/wavely_logo.dart';

/// Phase 12: branded splash with a smooth fade-in.
///
/// Shown by [SplashGate] on cold start: the neon-glass logo fades in over
/// ~600 ms, holds ~700 ms, then fades out over ~300 ms and unmounts — the
/// router content is already mounted underneath, so the hand-off is a
/// pure cross-fade (no blank frame, no extra route).
class WavelySplash extends StatelessWidget {
  /// Creates the splash (pass the fade animation to drive the opacity).
  const WavelySplash({required this.fade, super.key});

  /// 0..1 opacity animation for the whole splash surface.
  final Animation<double> fade;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: FadeTransition(
        opacity: fade,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const WavelyLogo(size: 132),
              const SizedBox(height: 16),
              Text(
                'Wavely',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gate that overlays [WavelySplash] above the app for one fade-in cycle.
///
/// Mounts the child immediately (the router builds beneath the splash),
/// animates the splash in, holds it briefly, fades out and removes
/// itself. Idempotent: after [totalDuration] the gate is inert.
class SplashGate extends StatefulWidget {
  /// Wraps the routed [child] with the splash overlay.
  const SplashGate({required this.child, super.key});

  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SplashTiming.total,
  )..forward();

  // Fade-in for the first 45% of the timeline, fade-out over the last 20%.
  late final Animation<double> _fade = TweenSequence<double>(<TweenSequenceItem<double>>[
    TweenSequenceItem<double>(
      tween: Tween<double>(begin: 0, end: 1)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 45,
    ),
    TweenSequenceItem<double>(tween: ConstantTween<double>(1), weight: 35),
    TweenSequenceItem<double>(
      tween: Tween<double>(begin: 1, end: 0)
          .chain(CurveTween(curve: Curves.easeIn)),
      weight: 20,
    ),
  ]).animate(_controller);

  /// Timeline of the splash: 600 ms in, 470 ms hold, 260 ms out (~1.33 s).
  static const SplashTiming = _SplashTimings();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        // Fade out fully before removing the overlay (no pop-in of the
        // underlying content).
        AnimatedBuilder(
          animation: _fade,
          builder: (context, _) {
            if (_controller.isCompleted) {
              return const SizedBox.shrink();
            }
            return WavelySplash(fade: _fade);
          },
        ),
      ],
    );
  }
}

/// Named durations for the splash timeline (kept together so the curve
/// weights and the controller duration can never drift apart).
class _SplashTimings {
  const _SplashTimings();

  static const double _inWeight = 0.45;
  static const double _holdWeight = 0.35;
  static const double _outWeight = 0.20;

  /// Total controller duration; the phase boundaries derive from the
  /// tween weights.
  Duration get total => const Duration(milliseconds: 1330);

  double get inWeight => _inWeight;
  double get holdWeight => _holdWeight;
  double get outWeight => _outWeight;
}

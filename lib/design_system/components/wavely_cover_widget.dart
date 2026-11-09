import 'package:flutter/material.dart';
import 'package:wavely/design_system/components/track_tile.dart';
import 'package:wavely/design_system/components/wavely_cover.dart';

/// A square piece of cover art that ALWAYS renders real artwork when the
/// file exists and the designed gradient fallback otherwise (v1.0.2
/// "no purple boxes" mandate).
///
/// This is the one shared cover widget used by the Musicolet sheets, the
/// desktop playbar, the desktop side panels and every other surface that
/// shows a standalone cover. [WavelyCoverFallback] guarantees the
/// never-a-letter gradient + music-note look.
class WavelyCover extends StatelessWidget {
  const WavelyCover({
    required this.label,
    this.coverPath,
    this.borderRadius,
    super.key,
  });

  /// Label used to seed the fallback gradient (track / album / playlist
  /// title). Deterministic per label.
  final String label;

  /// File path of the embedded artwork extracted by the library scanner.
  final String? coverPath;

  /// Optional corner rounding (defaults to slightly rounded, Musicolet
  /// style).
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final provider = wavelyCoverProvider(coverPath);
    final radius = borderRadius ?? BorderRadius.circular(6);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox.expand(
        child: provider != null
            ? Image(
                image: provider,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => WavelyCoverFallback(label: label),
              )
            : WavelyCoverFallback(label: label),
      ),
    );
  }
}

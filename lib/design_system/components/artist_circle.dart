import 'package:flutter/material.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/design_system/components/track_tile.dart';
import 'package:wavely/design_system/components/wavely_cover.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';

/// Circular artist avatar.
///
/// Shows cover art when [coverPath] is set (with a [WavelyCoverFallback]
/// error fallback), otherwise the accent-gradient initial. The tappable
/// area is at least AppConstants.touchTargetMin even for small radii.
class ArtistCircle extends StatelessWidget {
  const ArtistCircle({
    required this.name,
    this.coverPath,
    this.radius = 28,
    this.onTap,
    super.key,
  });

  final String name;
  final String? coverPath;

  /// Avatar radius in logical pixels (visual diameter is `2 * radius`).
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;
    final touchSize = diameter < AppConstants.touchTargetMin
        ? AppConstants.touchTargetMin
        : diameter;
    return Tooltip(
      message: name,
      child: Semantics(
        button: onTap != null,
        label: name,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: touchSize,
            height: touchSize,
            child: Center(
              child: ClipOval(child: _art(diameter)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _art(double diameter) {
    final provider = wavelyCoverProvider(coverPath);
    if (provider != null) {
      return Image(
        image: provider,
        width: diameter,
        height: diameter,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => WavelyCoverFallback(label: name),
      );
    }
    return WavelyCoverFallback(label: name);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Phase 12: the Wavely brand logo.
///
/// Renders the shipped neon-glass SVG (`assets/brand/wavely_logo.svg`):
/// a stylized 'W' over a soundwave, on a frosted-glass tile. Sized by the
/// surrounding box (aspect ratio 1:1).
class WavelyLogo extends StatelessWidget {
  /// Creates the logo. [size] is optional — omit it to fill the parent.
  const WavelyLogo({this.size, super.key});

  final double? size;

  @override
  Widget build(BuildContext context) {
    final picture = SvgPicture.asset(
      'assets/brand/wavely_logo.svg',
      width: size,
      height: size,
      semanticsLabel: 'Wavely logo',
    );
    if (size == null) {
      return picture;
    }
    return SizedBox(width: size, height: size, child: picture);
  }
}

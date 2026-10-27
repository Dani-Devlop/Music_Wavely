import 'package:flutter/material.dart';
import 'package:wavely/design_system/tokens/colors.dart';

/// Elevation shadows tuned for glassy surfaces.
abstract final class WavelyShadows {
  static List<BoxShadow> get dark => const <BoxShadow>[
        BoxShadow(
          color: WavelyDarkColors.shadow,
          offset: Offset(0, 8),
          blurRadius: 32,
        ),
      ];

  static List<BoxShadow> get light => const <BoxShadow>[
        BoxShadow(
          color: WavelyLightColors.shadow,
          offset: Offset(0, 8),
          blurRadius: 24,
        ),
      ];
}

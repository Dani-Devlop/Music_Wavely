import 'package:flutter/material.dart';

/// Luminance midpoint used to classify colors as dark or light.
const double _midLuminance = 0.5;

/// Color math helpers shared by tokens and UI code.
extension ColorX on Color {
  /// Returns the color mixed towards white by [amount] (0.0 - 1.0).
  Color lighten(double amount) => Color.lerp(this, Colors.white, amount)!;

  /// Returns the color mixed towards black by [amount] (0.0 - 1.0).
  Color darken(double amount) => Color.lerp(this, Colors.black, amount)!;

  /// True when the perceptual luminance is below the mid point.
  bool get isDark => computeLuminance() < _midLuminance;

  /// Hex string in `#RRGGBB` form (alpha is ignored).
  String get toHex {
    final argb = toARGB32();
    final rgb = argb & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

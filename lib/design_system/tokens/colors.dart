import 'package:flutter/material.dart';

/// Accent selection for the whole app (switchable in settings).
enum WavelyAccent { purple, green }

/// Resolves a [WavelyAccent] to its concrete [AccentColors] token set.
extension WavelyAccentX on WavelyAccent {
  AccentColors get colors => switch (this) {
        WavelyAccent.purple => AccentColors.purple,
        WavelyAccent.green => AccentColors.green,
      };
}

/// Immutable accent token set (accent, hover, gradient start).
final class AccentColors {
  const AccentColors({
    required this.accent,
    required this.hover,
    required this.gradientStart,
  });

  static const AccentColors purple = AccentColors(
    accent: Color(0xFF7C5CFF),
    hover: Color(0xFF9B7BFF),
    gradientStart: Color(0xFF5B3FD9),
  );

  static const AccentColors green = AccentColors(
    accent: Color(0xFF1DB954),
    hover: Color(0xFF1ED760),
    gradientStart: Color(0xFF0FA34A),
  );

  final Color accent;
  final Color hover;
  final Color gradientStart;
}

/// Dark-mode color tokens.
abstract final class WavelyDarkColors {
  static const Color bgBase = Color(0xFF0A0E14);
  static const Color surface = Color.fromRGBO(20, 25, 35, 0.6);
  static const Color elevated = Color.fromRGBO(30, 38, 52, 0.7);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB8BFC9);
  static const Color textTertiary = Color(0xFF6B7280);
  static const Color borderGlass = Color(0x14FFFFFF);
  static const Color shadow = Color(0x66000000);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color success = Color(0xFF10B981);
}

/// Light-mode color tokens.
abstract final class WavelyLightColors {
  static const Color bgBase = Color(0xFFF5F7FA);
  static const Color surface = Color.fromRGBO(255, 255, 255, 0.7);
  static const Color elevated = Color.fromRGBO(255, 255, 255, 0.85);
  static const Color textPrimary = Color(0xFF0A0E14);
  static const Color textSecondary = Color(0xFF5A6270);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color borderGlass = Color(0x0F000000);
  static const Color shadow = Color(0x14000000);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color success = Color(0xFF10B981);
}

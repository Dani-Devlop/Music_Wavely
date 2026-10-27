import 'package:flutter/material.dart';
import 'package:wavely/design_system/tokens/colors.dart';

/// Semantic color contract of the Wavely design system.
///
/// Widgets read these through `context.wavelyColors` instead of touching
/// raw [WavelyDarkColors] / [WavelyLightColors] tokens, so switching
/// brightness or accent happens via the ambient [Theme].
class WavelySemanticColors extends ThemeExtension<WavelySemanticColors> {
  const WavelySemanticColors({
    required this.bgBase,
    required this.surface,
    required this.elevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.borderGlass,
    required this.shadowColor,
    required this.error,
    required this.warning,
    required this.success,
    required this.accentColors,
    required this.isDark,
  });

  factory WavelySemanticColors.dark(WavelyAccent accent) {
    final accentColors = accent.colors;
    return WavelySemanticColors(
      bgBase: WavelyDarkColors.bgBase,
      surface: WavelyDarkColors.surface,
      elevated: WavelyDarkColors.elevated,
      textPrimary: WavelyDarkColors.textPrimary,
      textSecondary: WavelyDarkColors.textSecondary,
      textTertiary: WavelyDarkColors.textTertiary,
      borderGlass: WavelyDarkColors.borderGlass,
      shadowColor: WavelyDarkColors.shadow,
      error: WavelyDarkColors.error,
      warning: WavelyDarkColors.warning,
      success: WavelyDarkColors.success,
      accentColors: accentColors,
      isDark: true,
    );
  }

  factory WavelySemanticColors.light(WavelyAccent accent) {
    final accentColors = accent.colors;
    return WavelySemanticColors(
      bgBase: WavelyLightColors.bgBase,
      surface: WavelyLightColors.surface,
      elevated: WavelyLightColors.elevated,
      textPrimary: WavelyLightColors.textPrimary,
      textSecondary: WavelyLightColors.textSecondary,
      textTertiary: WavelyLightColors.textTertiary,
      borderGlass: WavelyLightColors.borderGlass,
      shadowColor: WavelyLightColors.shadow,
      error: WavelyLightColors.error,
      warning: WavelyLightColors.warning,
      success: WavelyLightColors.success,
      accentColors: accentColors,
      isDark: false,
    );
  }

  final Color bgBase;
  final Color surface;
  final Color elevated;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color borderGlass;
  final Color shadowColor;
  final Color error;
  final Color warning;
  final Color success;
  final AccentColors accentColors;
  final bool isDark;

  @override
  WavelySemanticColors copyWith({
    Color? bgBase,
    Color? surface,
    Color? elevated,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? borderGlass,
    Color? shadowColor,
    Color? error,
    Color? warning,
    Color? success,
    AccentColors? accentColors,
    bool? isDark,
  }) =>
      WavelySemanticColors(
        bgBase: bgBase ?? this.bgBase,
        surface: surface ?? this.surface,
        elevated: elevated ?? this.elevated,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
        borderGlass: borderGlass ?? this.borderGlass,
        shadowColor: shadowColor ?? this.shadowColor,
        error: error ?? this.error,
        warning: warning ?? this.warning,
        success: success ?? this.success,
        accentColors: accentColors ?? this.accentColors,
        isDark: isDark ?? this.isDark,
      );

  @override
  WavelySemanticColors lerp(covariant WavelySemanticColors? other, double t) {
    if (other == null) {
      return this;
    }
    return WavelySemanticColors(
      bgBase: Color.lerp(bgBase, other.bgBase, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      borderGlass: Color.lerp(borderGlass, other.borderGlass, t)!,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t)!,
      error: Color.lerp(error, other.error, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      accentColors: t < 0.5 ? accentColors : other.accentColors,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WavelySemanticColors &&
          other.bgBase == bgBase &&
          other.surface == surface &&
          other.elevated == elevated &&
          other.textPrimary == textPrimary &&
          other.textSecondary == textSecondary &&
          other.textTertiary == textTertiary &&
          other.borderGlass == borderGlass &&
          other.shadowColor == shadowColor &&
          other.error == error &&
          other.warning == warning &&
          other.success == success &&
          other.accentColors == accentColors &&
          other.isDark == isDark;

  @override
  int get hashCode => Object.hash(
        bgBase,
        surface,
        elevated,
        textPrimary,
        textSecondary,
        textTertiary,
        borderGlass,
        shadowColor,
        error,
        warning,
        success,
        accentColors,
        isDark,
      );
}

/// Exposes [WavelySemanticColors] from any context below a Wavely theme.
extension WavelySemanticColorsContextX on BuildContext {
  WavelySemanticColors get wavelyColors =>
      Theme.of(this).extension<WavelySemanticColors>()!;
}

import 'package:flutter/material.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/design_system/tokens/colors.dart';
import 'package:wavely/design_system/tokens/radii.dart';
import 'package:wavely/design_system/tokens/typography.dart';

/// Builds the two Wavely themes (light/dark) for a given accent token set.
///
/// Phase 10: accepts the concrete [AccentColors] (named palette OR the
/// adaptive accent extracted from album art) plus the AMOLED flag.
class WavelyThemes {
  const WavelyThemes._();

  static ThemeData light(AccentColors colors) => _build(colors, Brightness.light);

  static ThemeData dark(AccentColors colors, {bool amoled = false}) =>
      _build(colors, Brightness.dark, amoled: amoled);

  static ThemeData _build(
    AccentColors colors,
    Brightness brightness, {
    bool amoled = false,
  }) {
    final semantic = brightness == Brightness.dark
        ? WavelySemanticColors.darkAccent(colors, amoled: amoled)
        : WavelySemanticColors.lightAccent(colors);
    final accentColor = colors.accent;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: brightness,
    ).copyWith(surface: semantic.surface);
    // AMOLED: scaffold goes pure black; cards keep the near-black surfaces.
    final scaffold = amoled && brightness == Brightness.dark
        ? const Color(0xFF000000)
        : semantic.bgBase;

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffold,
      extensions: <ThemeExtension<dynamic>>[semantic],
      appBarTheme: AppBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: WavelyTypography.title18(color: semantic.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: semantic.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: semantic.surface,
        hintStyle: WavelyTypography.body14(color: semantic.textTertiary),
        border: _outlineBorder(semantic.borderGlass),
        enabledBorder: _outlineBorder(semantic.borderGlass),
        focusedBorder: _outlineBorder(accentColor),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: accentColor.withValues(alpha: 0.24),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accentColor,
        inactiveTrackColor: semantic.borderGlass,
        thumbColor: colors.hover,
        overlayColor: accentColor.withValues(alpha: 0.12),
        valueIndicatorColor: accentColor,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accentColor,
        linearTrackColor: semantic.borderGlass,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: semantic.elevated,
        contentTextStyle:
            WavelyTypography.body14Medium(color: semantic.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: AppRadii.bMd),
      ),
      textTheme: _textTheme(semantic),
      iconTheme: IconThemeData(color: semantic.textPrimary),
      dividerTheme: DividerThemeData(
        color: semantic.borderGlass,
        thickness: 1,
        space: 1,
      ),
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  static OutlineInputBorder _outlineBorder(Color color) => OutlineInputBorder(
        borderRadius: AppRadii.bMd,
        borderSide: BorderSide(color: color),
      );

  static TextTheme _textTheme(WavelySemanticColors c) => TextTheme(
        displayLarge: WavelyTypography.display32(color: c.textPrimary),
        displayMedium: WavelyTypography.display24(color: c.textPrimary),
        titleLarge: WavelyTypography.title20(color: c.textPrimary),
        titleMedium: WavelyTypography.title18(color: c.textPrimary),
        titleSmall: WavelyTypography.body14Medium(color: c.textPrimary),
        bodyLarge: WavelyTypography.body14(color: c.textPrimary),
        bodyMedium: WavelyTypography.body14(color: c.textSecondary),
        bodySmall: WavelyTypography.caption12(color: c.textTertiary),
        labelLarge: WavelyTypography.body14Medium(color: c.textPrimary),
        labelMedium: WavelyTypography.caption12(color: c.textSecondary),
        labelSmall: WavelyTypography.micro10(color: c.textTertiary),
      );
}

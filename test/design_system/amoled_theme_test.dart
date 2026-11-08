// Phase 10.1 — AMOLED theme, adaptive accent tokens, blur & radius scales.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/design_system/themes/app_theme.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/design_system/tokens/blur.dart';
import 'package:wavely/design_system/tokens/colors.dart';
import 'package:wavely/design_system/tokens/radii.dart';
import 'package:wavely/app/theme_provider.dart' show resolveAccentColors;
import 'package:wavely/features/settings/domain/settings.dart';

void main() {
  group('AMOLED theme (Phase 10.1)', () {
    test('dark AMOLED surfaces go pure black', () {
      final theme = WavelyThemes.dark(
        WavelyAccent.purple.colors,
        amoled: true,
      );
      final colors = theme.extension<WavelySemanticColors>()!;
      expect(colors.bgBase, const Color(0xFF000000));
      expect(colors.isDark, isTrue);
      expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
    });

    test('regular dark keeps the glassy palette', () {
      final theme = WavelyThemes.dark(WavelyAccent.purple.colors);
      final colors = theme.extension<WavelySemanticColors>()!;
      expect(colors.bgBase, WavelyDarkColors.bgBase);
      expect(theme.scaffoldBackgroundColor, WavelyDarkColors.bgBase);
    });

    test('AMOLED accent stays untouched (accentColors identical)', () {
      final amoled = WavelyThemes.dark(
        WavelyAccent.green.colors,
        amoled: true,
      );
      final regular = WavelyThemes.dark(WavelyAccent.green.colors);
      expect(
        (amoled.extension<WavelySemanticColors>()!).accentColors.accent,
        (regular.extension<WavelySemanticColors>()!).accentColors.accent,
      );
    });

    test('light themes ignore the AMOLED flag', () {
      final light = WavelyThemes.light(WavelyAccent.purple.colors);
      final colors = light.extension<WavelySemanticColors>()!;
      expect(colors.bgBase, WavelyLightColors.bgBase);
    });
  });

  group('AccentColors.custom (adaptive seed)', () {
    test('hover is lighter and gradientStart darker than the accent', () {
      final custom = AccentColors.custom(const Color(0xFFE44B3C));
      final hslAccent = HSLColor.fromColor(const Color(0xFFE44B3C));
      expect(
        HSLColor.fromColor(custom.hover).lightness,
        greaterThan(hslAccent.lightness),
      );
      expect(
        HSLColor.fromColor(custom.gradientStart).lightness,
        lessThan(hslAccent.lightness),
      );
    });
  });

  group('Design-token scales (Phase 10.1 blur/radius settings)', () {
    setUp(() {
      WavelyBlur.scale = 1;
      AppRadii.scale = 1;
    });
    tearDown(() {
      WavelyBlur.scale = 1;
      AppRadii.scale = 1;
    });

    test('blur tokens multiply through the runtime scale', () {
      WavelyBlur.scale = 2;
      expect(
        WavelyBlur.surface,
        closeTo(48, 0.01),
        reason: 'AppConstants.blurSigmaSurface is 24 in the design budget',
      );
      expect(WavelyBlur.elevated, closeTo(64, 0.01));
      WavelyBlur.scale = 0;
      expect(WavelyBlur.surface, 0);
      expect(WavelyBlur.elevated, 0);
    });

    test('radius tokens multiply through the runtime scale', () {
      AppRadii.scale = 1.5;
      expect(AppRadii.sm, 12);
      expect(AppRadii.md, 18);
      expect(AppRadii.lg, 24);
      AppRadii.scale = 0.5;
      expect(AppRadii.lg, 8);
      // Pill never scales (progress bars, switches).
      expect(AppRadii.pill, 999);
    });
  });

  group('AppSettings Phase-10 defaults', () {
    test('AMOLED/adaptive/blur/radius ship with documented defaults', () {
      const settings = AppSettings();
      expect(settings.amoled, isFalse);
      expect(settings.adaptiveAccent, isFalse);
      expect(settings.adaptiveAccentValue, 0);
      expect(settings.blurScale, 1.0);
      expect(settings.radiusScale, 1.0);
    });

    test('resolveAccentColors honors the adaptive value', () {
      const settings = AppSettings();
      expect(
        resolveAccentColors(settings),
        same(settings.accent.toWavelyAccent.colors),
      );
    });
  });
}

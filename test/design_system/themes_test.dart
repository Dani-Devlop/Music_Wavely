/// Authored, awaiting local run (Task 2-f).
///
/// Theme factory contract for light/dark × purple/green: every
/// [WavelyThemes] combination produces a ThemeData with a non-null color
/// scheme carrying the token colors, the exact dark/light token values on
/// the scaffold/semantic extension, and — pumped through a MaterialApp —
/// a reachable `WavelySemanticColors` extension on Theme.of(context) for
/// all four combinations.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/design_system/design_system.dart';

void main() {
  group('WavelyThemes factories', () {
    test('light/dark × purple/green build themed, token-backed ThemeData',
        () {
      final combos = <(WavelyAccent, bool)>[
        (WavelyAccent.purple, false),
        (WavelyAccent.purple, true),
        (WavelyAccent.green, false),
        (WavelyAccent.green, true),
      ];
      for (final (accent, dark) in combos) {
        final theme =
            dark ? WavelyThemes.dark(accent) : WavelyThemes.light(accent);
        final semantic =
            theme.extension<WavelySemanticColors>()! as WavelySemanticColors;
        final tokens = accent.colors;

        // Color scheme exists and mirrors the semantic surface.
        expect(theme.colorScheme.surface, semantic.surface);
        // Scaffold background is the exact bgBase token.
        expect(
          theme.scaffoldBackgroundColor,
          dark ? WavelyDarkColors.bgBase : WavelyLightColors.bgBase,
        );
        // Semantic extension carries the exact token values.
        expect(semantic.bgBase,
            dark ? WavelyDarkColors.bgBase : WavelyLightColors.bgBase);
        expect(semantic.error, dark
            ? WavelyDarkColors.error
            : WavelyLightColors.error);
        expect(semantic.accentColors.accent, tokens.accent);
        expect(semantic.accentColors.hover, tokens.hover);
        expect(semantic.accentColors.gradientStart, tokens.gradientStart);
        expect(semantic.isDark, dark);
        // Accent tokens per enum value.
        if (accent == WavelyAccent.purple) {
          expect(tokens.accent, const Color(0xFF7C5CFF));
        } else {
          expect(tokens.accent, const Color(0xFF1DB954));
        }
      }
    });

    test('the semantic extension is a real ThemeExtension', () {
      final light =
          WavelyThemes.light(WavelyAccent.purple)
              .extension<WavelySemanticColors>();
      final dark =
          WavelyThemes.dark(WavelyAccent.green)
              .extension<WavelySemanticColors>();
      expect(light, isA<ThemeExtension<WavelySemanticColors>>());
      expect(dark, isA<ThemeExtension<WavelySemanticColors>>());
      // lerp keeps both sides of the accent switch deterministic.
      final lerped = light!.lerp(dark, 0.75);
      expect(lerped.accentColors, dark!.accentColors);
      expect(lerped.isDark, dark.isDark);
    });
  });

  group('semantic extension reachability', () {
    Future<WavelySemanticColors?> _pumpAndProbe(
      WidgetTester tester, {
      required WavelyAccent accent,
      required bool dark,
    }) async {
      WavelySemanticColors? probed;
      await tester.pumpWidget(
        MaterialApp(
          theme: dark
              ? WavelyThemes.dark(accent)
              : WavelyThemes.light(accent),
          home: Builder(
            builder: (BuildContext context) {
              probed = Theme.of(context).extension<WavelySemanticColors>();
              // The context accessor must resolve for every combination.
              expect(context.wavelyColors, same(probed));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return probed;
    }

    testWidgets('Theme.of(context) exposes the extension on all four '
        'theme combinations', (tester) async {
      for (final accent in WavelyAccent.values) {
        for (final dark in <bool>[false, true]) {
          final semantic = await _pumpAndProbe(
            tester,
            accent: accent,
            dark: dark,
          );
          expect(semantic, isNotNull);
          expect(semantic!.isDark, dark);
          expect(semantic.accentColors, accent.colors);
          expect(
            semantic.bgBase,
            dark ? WavelyDarkColors.bgBase : WavelyLightColors.bgBase,
          );
        }
      }
    });
  });
}

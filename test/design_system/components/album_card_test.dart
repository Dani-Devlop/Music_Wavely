/// Authored, awaiting local run (Task 2-f).
///
/// [AlbumCard] smoke test: renders title/artist captions and the gradient
/// fallback initial, fires [AlbumCard.onTap], and renders under BOTH the
/// light and dark Wavely themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/design_system/components/album_card.dart';

import '../helpers/pump_theme.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool dark,
    VoidCallback? onTap,
  }) =>
      pumpThemed(
        tester,
        dark: dark,
        child: SizedBox(
          width: 200,
          child: AlbumCard(
            title: 'Neon Rivers',
            artist: 'Velvet Echo',
            onTap: onTap,
          ),
        ),
      );

  for (final dark in <bool>[false, true]) {
    testWidgets('renders captions + fallback initial '
        '(${dark ? 'dark' : 'light'} theme)', (tester) async {
      await pump(tester, dark: dark);
      expect(find.text('Neon Rivers'), findsOneWidget);
      expect(find.text('Velvet Echo'), findsOneWidget);
      // No coverPath → WavelyCoverFallback renders the initial.
      expect(find.text('N'), findsOneWidget);
    });

    testWidgets('onTap fires (${dark ? 'dark' : 'light'} theme)',
        (tester) async {
      var taps = 0;
      await pump(tester, dark: dark, onTap: () => taps++);
      await tester.tap(find.text('Neon Rivers'));
      await tester.pump();
      expect(taps, 1);
    });
  }
}

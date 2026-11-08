/// Authored, awaiting local run (Task 2-f).
///
/// [AlbumCard] smoke test: renders title/artist captions and the premium
/// music-note fallback (v1.0.1-beta3: never a letter tile), fires
/// [AlbumCard.onTap], and renders under BOTH the light and dark themes.
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
    testWidgets('renders captions + music-note fallback '
        '(${dark ? 'dark' : 'light'} theme)', (tester) async {
      await pump(tester, dark: dark);
      expect(find.text('Neon Rivers'), findsOneWidget);
      expect(find.text('Velvet Echo'), findsOneWidget);
      // No coverPath → WavelyCoverFallback renders the premium glyph
      // (owner spec: a hash-gradient art tile, never a letter).
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
      expect(find.text('N'), findsNothing);
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

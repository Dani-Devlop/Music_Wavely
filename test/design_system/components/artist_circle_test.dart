/// Authored, awaiting local run (Task 2-f).
///
/// [ArtistCircle] smoke test: renders the premium music-note fallback for
/// a missing cover (v1.0.1-beta3: never a letter tile), exposes the name
/// tooltip, fires [ArtistCircle.onTap] (with the padded touch target), and
/// renders under BOTH the light and dark Wavely themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/design_system/components/artist_circle.dart';

import '../helpers/pump_theme.dart';

void main() {
  for (final dark in <bool>[false, true]) {
    testWidgets('renders the music-note fallback + tooltip '
        '(${dark ? 'dark' : 'light'} theme)', (tester) async {
      await pumpThemed(
        tester,
        dark: dark,
        child: const ArtistCircle(name: 'Aurora'),
      );
      // Premium fallback shows the glowing white note, never a letter.
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
      expect(find.text('A'), findsNothing);
      expect(find.byTooltip('Aurora'), findsOneWidget);
    });

    testWidgets('onTap fires (${dark ? 'dark' : 'light'} theme)',
        (tester) async {
      var taps = 0;
      await pumpThemed(
        tester,
        dark: dark,
        child: ArtistCircle(name: 'Aurora', onTap: () => taps++),
      );
      await tester.tap(find.byType(ArtistCircle));
      await tester.pump();
      expect(taps, 1);
    });
  }
}

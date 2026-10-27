/// Authored, awaiting local run (Task 2-f).
///
/// [ArtistCircle] smoke test: renders the initial fallback for a missing
/// cover, exposes the name tooltip, fires [ArtistCircle.onTap] (with the
/// padded touch target), and renders under BOTH the light and dark Wavely
/// themes.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/design_system/components/artist_circle.dart';

import '../helpers/pump_theme.dart';

void main() {
  for (final dark in <bool>[false, true]) {
    testWidgets('renders the initial fallback + tooltip '
        '(${dark ? 'dark' : 'light'} theme)', (tester) async {
      await pumpThemed(
        tester,
        dark: dark,
        child: const ArtistCircle(name: 'Aurora'),
      );
      // Gradient fallback shows the first character of the name.
      expect(find.text('A'), findsOneWidget);
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

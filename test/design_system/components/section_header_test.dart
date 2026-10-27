/// Authored, awaiting local run (Task 2-f).
///
/// [SectionHeader] smoke test: renders the title, shows the trailing
/// action only when label AND callback are provided, fires the callback,
/// and renders under BOTH the light and dark Wavely themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/design_system/components/section_header.dart';

import '../helpers/pump_theme.dart';

void main() {
  for (final dark in <bool>[false, true]) {
    String label(bool d) => d ? 'dark' : 'light';

    testWidgets('title + action render and fire (${label(dark)} theme)',
        (tester) async {
      var actions = 0;
      await pumpThemed(
        tester,
        dark: dark,
        child: SectionHeader(
          title: 'Recently played',
          actionLabel: 'See all',
          onAction: () => actions++,
        ),
      );
      expect(find.text('Recently played'), findsOneWidget);
      expect(find.text('See all'), findsOneWidget);
      await tester.tap(find.text('See all'));
      await tester.pump();
      expect(actions, 1);
    });

    testWidgets('no action button without a callback (${label(dark)} '
        'theme)', (tester) async {
      await pumpThemed(
        tester,
        dark: dark,
        child: const SectionHeader(title: 'Just a title'),
      );
      expect(find.text('Just a title'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
    });
  }
}

/// Authored, awaiting local run (Task 2-f).
///
/// [EmptyState] smoke test: renders the icon, title and subtitle, shows
/// the CTA only when label AND callback are provided, fires the callback,
/// and renders under BOTH the light and dark Wavely themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/design_system/components/empty_state.dart';

import '../helpers/pump_theme.dart';

void main() {
  for (final dark in <bool>[false, true]) {
    testWidgets('renders icon, title, subtitle and CTA '
        '(${dark ? 'dark' : 'light'} theme)', (tester) async {
      var ctaTaps = 0;
      await pumpThemed(
        tester,
        dark: dark,
        child: EmptyState(
          icon: Icons.music_off_outlined,
          title: 'Nothing here yet',
          subtitle: 'Add some music to your library.',
          ctaLabel: 'Browse files',
          onCta: () => ctaTaps++,
        ),
      );
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.text('Add some music to your library.'), findsOneWidget);
      expect(find.byIcon(Icons.music_off_outlined), findsOneWidget);
      await tester.tap(find.text('Browse files'));
      await tester.pump();
      expect(ctaTaps, 1);
    });

    testWidgets('no CTA rendered without label/callback '
        '(${dark ? 'dark' : 'light'} theme)', (tester) async {
      await pumpThemed(
        tester,
        dark: dark,
        child: const EmptyState(
          icon: Icons.hourglass_empty,
          title: 'Loading…',
        ),
      );
      expect(find.text('Loading…'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  }
}

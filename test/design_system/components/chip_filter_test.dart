/// Authored, awaiting local run (Task 2-f).
///
/// [ChipFilter] smoke test: renders the label (and optional icon), toggles
/// [ChipFilter.onSelected] with the INVERTED selection on tap, and renders
/// under BOTH the light and dark Wavely themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/design_system/components/chip_filter.dart';

import '../helpers/pump_theme.dart';

void main() {
  for (final dark in <bool>[false, true]) {
    for (final selected in <bool>[false, true]) {
      testWidgets(
          'label renders and tap inverts selection '
          '(selected: $selected, ${dark ? 'dark' : 'light'})',
          (tester) async {
        final selections = <bool>[];
        await pumpThemed(
          tester,
          dark: dark,
          child: ChipFilter(
            label: 'Focus',
            selected: selected,
            onSelected: selections.add,
            icon: Icons.headphones,
          ),
        );
        expect(find.text('Focus'), findsOneWidget);
        expect(find.byIcon(Icons.headphones), findsOneWidget);
        await tester.tap(find.text('Focus'));
        await tester.pump();
        expect(selections, <bool>[!selected]);
      });
    }
  }
}

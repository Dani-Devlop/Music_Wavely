/// Authored, awaiting local run (Task 2-f).
///
/// [ExplicitBadge] smoke test: renders the "E" glyph at the requested
/// size, carries the 'Explicit' semantics label, and renders under BOTH
/// the light and dark Wavely themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/design_system/components/explicit_badge.dart';

import '../helpers/pump_theme.dart';

void main() {
  for (final dark in <bool>[false, true]) {
    testWidgets('renders the E mark with semantics '
        '(${dark ? 'dark' : 'light'} theme)', (tester) async {
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);
      await pumpThemed(
        tester,
        dark: dark,
        child: const ExplicitBadge(size: 20),
      );
      expect(find.text('E'), findsOneWidget);
      final box = tester.getSize(find.byType(ExplicitBadge));
      expect(box.width, 20);
      expect(box.height, 20);
      expect(find.bySemanticsLabel('Explicit'), findsOneWidget);
    });
  }
}

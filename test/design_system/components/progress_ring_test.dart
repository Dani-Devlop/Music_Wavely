/// Authored, awaiting local run (Task 2-f).
///
/// [ProgressRing] smoke test: a determinate ring clamps and forwards its
/// value, an indeterminate ring passes null through, sizing/stroke params
/// reach the indicator, and it renders under BOTH the light and dark
/// Wavely themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/design_system/components/progress_ring.dart';

import '../helpers/pump_theme.dart';

void main() {
  for (final dark in <bool>[false, true]) {
    String label(bool d) => d ? 'dark' : 'light';

    testWidgets('determinate value reaches the indicator '
        '(${label(dark)} theme)', (tester) async {
      await pumpThemed(
        tester,
        dark: dark,
        child: const ProgressRing(value: 0.5, size: 48, strokeWidth: 5),
      );
      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.value, 0.5);
      expect(indicator.strokeWidth, 5);
      // The 48dp SizedBox wraps the ring.
      expect(
        tester.getSize(find.byType(ProgressRing)),
        const Size(48, 48),
      );
    });

    testWidgets('null value renders the indeterminate spinner '
        '(${label(dark)} theme)', (tester) async {
      await pumpThemed(
        tester,
        dark: dark,
        child: const ProgressRing(),
      );
      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.value, isNull);
    });

    testWidgets('values above 1 are clamped (${label(dark)} theme)',
        (tester) async {
      await pumpThemed(
        tester,
        dark: dark,
        child: const ProgressRing(value: 1.7),
      );
      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.value, 1);
    });
  }
}

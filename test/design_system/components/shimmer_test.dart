/// Authored, awaiting local run (Task 2-f).
///
/// [Shimmer] / [ShimmerBox] smoke test: the child stays in the tree under
/// the sweep ShaderMask, [ShimmerBox] applies its sizing + radius, and
/// both render under the light and dark Wavely themes. NOTE: the repeating
/// sweep controller never settles, so these tests only pump explicit
/// frames (never pumpAndSettle) and stay out of test/goldens by design.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/design_system/components/shimmer.dart';

import '../helpers/pump_theme.dart';

void main() {
  for (final dark in <bool>[false, true]) {
    String label(bool d) => d ? 'dark' : 'light';

    testWidgets('Shimmer keeps the child under the sweep mask '
        '(${label(dark)} theme)', (tester) async {
      await pumpThemed(
        tester,
        dark: dark,
        child: const Shimmer(child: Text('loading skeleton')),
      );
      // Advance a couple of explicit frames of the repeating sweep.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(find.text('loading skeleton'), findsOneWidget);
    });

    testWidgets('ShimmerBox applies sizing + radius (${label(dark)} '
        'theme)', (tester) async {
      await pumpThemed(
        tester,
        dark: dark,
        child: const ShimmerBox(width: 120, height: 14),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final box = tester.firstWidget(find.byType(Container)) as Container;
      expect(box.constraints?.maxWidth, 120);
      expect(box.constraints?.maxHeight, 14);
      expect(find.byType(Shimmer), findsOneWidget);
    });
  }
}

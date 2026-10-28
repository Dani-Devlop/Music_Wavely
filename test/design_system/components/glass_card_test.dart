/// Authored, awaiting local run (Task 2-f).
///
/// [GlassCard] smoke test (ConsumerWidget): renders its child through the
/// backdrop-blur glass path by default, switches to the opaque solid path
/// when reduceTransparencyProvider is on, fires the optional [onTap], and
/// renders under BOTH the light and dark Wavely themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavely/design_system/components/glass_card.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';

import '../helpers/pump_theme.dart';

void main() {
  List<Override> _overrides(bool reduceTransparency) => <Override>[
        reduceTransparencyProvider
            .overrideWithValue(reduceTransparency),
      ];

  for (final dark in <bool>[false, true]) {
    testWidgets('renders the child through the backdrop-blur path '
        '(${dark ? 'dark' : 'light'} theme)', (tester) async {
      await pumpThemed(
        tester,
        dark: dark,
        overrides: _overrides(false),
        child: const GlassCard(child: Text('glassy content')),
      );
      expect(find.text('glassy content'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('reduce-transparency swaps to the solid path '
        '(${dark ? 'dark' : 'light'} theme)', (tester) async {
      await pumpThemed(
        tester,
        dark: dark,
        overrides: _overrides(true),
        child: const GlassCard(child: Text('glassy content')),
      );
      expect(find.text('glassy content'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('onTap fires (${dark ? 'dark' : 'light'} theme)',
        (tester) async {
      var taps = 0;
      await pumpThemed(
        tester,
        dark: dark,
        overrides: _overrides(false),
        child: GlassCard(
          onTap: () => taps++,
          child: const Text('tap me'),
        ),
      );
      await tester.tap(find.text('tap me'));
      await tester.pump();
      expect(taps, 1);
    });
  }
}

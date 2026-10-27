/// Authored, awaiting local run (Task 2-f).
///
/// [ErrorState] smoke test: renders the error icon, message and optional
/// detail, fires the mandatory retry callback, and renders under BOTH the
/// light and dark Wavely themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/design_system/components/error_state.dart';

import '../helpers/pump_theme.dart';

void main() {
  for (final dark in <bool>[false, true]) {
    testWidgets('renders icon + message + detail, retry fires '
        '(${dark ? 'dark' : 'light'} theme)', (tester) async {
      var retries = 0;
      await pumpThemed(
        tester,
        dark: dark,
        child: ErrorState(
          message: 'Sync failed',
          detail: 'HTTP 503 from the metadata service.',
          onRetry: () => retries++,
        ),
      );
      expect(find.text('Sync failed'), findsOneWidget);
      expect(
        find.text('HTTP 503 from the metadata service.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('detail is optional (${dark ? 'dark' : 'light'} theme)',
        (tester) async {
      await pumpThemed(
        tester,
        dark: dark,
        child: ErrorState(
          message: 'Something broke',
          onRetry: () {},
        ),
      );
      expect(find.text('Something broke'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  }
}

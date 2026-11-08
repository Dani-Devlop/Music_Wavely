// Phase 12 — Logo & splash.
//
// - the neon-glass SVG asset loads and renders through flutter_svg;
// - SplashGate fades in, holds, fades out and unmounts the overlay;
// - WavelyLogo honors an explicit size.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/app/splash.dart';
import 'package:wavely/design_system/components/wavely_logo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WavelyLogo', () {
    testWidgets('renders the shipped SVG asset at the requested size',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Center(child: WavelyLogo(size: 96))),
      );
      await tester.pumpAndSettle();

      final logo = find.byType(WavelyLogo);
      expect(logo, findsOneWidget);
      final sizedBox = tester.widget<SizedBox>(
        find
            .descendant(
              of: find.byType(WavelyLogo),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(sizedBox.width, 96);
      expect(sizedBox.height, 96);
    });
  });

  group('SplashGate', () {
    testWidgets('fades the splash in and hands off to the child',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SplashGate(child: Text('content'))),
      );

      // Splash overlay visible mid-fade.
      expect(find.byType(WavelySplash), findsOneWidget);
      expect(find.text('content'), findsOneWidget);

      // Advance through the whole timeline (in + hold + out ≈ 1.33 s).
      await tester.pumpAndSettle();

      // Overlay unmounted after the fade-out.
      expect(find.byType(WavelySplash), findsNothing);
      expect(find.text('content'), findsOneWidget);
    });
  });
}

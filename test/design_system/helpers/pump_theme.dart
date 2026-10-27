/// Authored, awaiting local run (Task 2-f).
///
/// Shared pumping helper for the design-system component smoke tests:
/// wraps the widget in a Scaffold inside a MaterialApp built with the REAL
/// [WavelyThemes] factories so `context.wavelyColors` resolves through the
/// semantic theme extension. Optional Riverpod overrides are applied for
/// the two Consumer components (GlassCard, MiniPlayer).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/design_system/design_system.dart';

/// Pumps [child] under the real Wavely theme (light/dark × accent).
Future<void> pumpThemed(
  WidgetTester tester, {
  required Widget child,
  bool dark = false,
  WavelyAccent accent = WavelyAccent.purple,
  List<Override> overrides = const <Override>[],
}) async {
  Widget app = MaterialApp(
    theme: dark ? WavelyThemes.dark(accent) : WavelyThemes.light(accent),
    home: Scaffold(body: Center(child: child)),
  );
  if (overrides.isNotEmpty) {
    app = ProviderScope(overrides: overrides, child: app);
  }
  await tester.pumpWidget(app);
  // One frame for post-layout animations; never pumpAndSettle here — the
  // shimmer's repeating controller would never settle.
  await tester.pump();
}

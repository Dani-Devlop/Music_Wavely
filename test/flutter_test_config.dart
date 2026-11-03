/// Stage 6 E2E — global test bootstrap.
///
/// Loads every font declared in the app pubspec (Sora, Inter, the Roboto
/// alias and MaterialIcons) into the test binding, once per test isolate,
/// before any test runs. Without this `flutter test` renders text with the
/// Ahem placeholder glyphs: the E2E screenshots produced by
/// `test/goldens/app_screenshots_test.dart` would be unreadable boxes.
///
/// `flutter_test_config.dart` is picked up automatically by the test runner
/// when it sits at `test/` — no test file needs to import it.
library;

import 'dart:async';

import 'package:golden_toolkit/golden_toolkit.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadAppFonts();
  return testMain();
}

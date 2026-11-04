// Widget tests for lib/features/settings/presentation/screens/
// update_screen.dart: every flow phase rendered through a fake
// UpdateService (no network, no platform channels).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/features/settings/data/update_providers.dart';
import 'package:wavely/features/settings/data/update_service.dart';
import 'package:wavely/features/settings/presentation/screens/update_screen.dart';

import '../../support/fake_update_service.dart';

UpdateCheckResult _availableResult() => UpdateCheckResult.available(
      currentVersion: '1.0.0',
      latestVersion: 'v1.0.1',
      releaseUrl:
          'https://github.com/Dani-Devlop/Music_Wavely/releases/tag/v1.0.1',
      releaseNotes: 'Auto-update system',
      assetUrl: 'https://github.com/x/wavely.msix',
      assetName: 'wavely.msix',
      assetSizeBytes: 1048576,
    );

Future<void> _pumpScreen(WidgetTester tester, UpdateService service) async {
  // Tall viewport: the notes card + buttons sit below the default test
  // fold (the same helper the discovery tests use).
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // GlassCard watches reduceTransparencyProvider → sharedPrefsProvider;
  // inject mock prefs exactly like the settings screen test does.
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: <Override>[
      sharedPrefsProvider.overrideWithValue(prefs),
      updateServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: WavelyThemes.dark(WavelyAccent.purple),
        home: const UpdateScreen(),
      ),
    ),
  );
  await tester.pump(); // post-frame auto-check kickoff
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the up-to-date state with the running version',
      (tester) async {
    final service = FakeUpdateService(
      checkResult: UpdateCheckResult.upToDate('1.0.0'),
    );
    await _pumpScreen(tester, service);

    expect(find.byKey(const Key('update-screen-up-to-date')), findsOneWidget);
    expect(find.text("You're up to date"), findsOneWidget);
    expect(find.text('Wavely 1.0.0 is the newest published release.'),
        findsOneWidget);
  });

  testWidgets('available state shows version jump, notes and the button',
      (tester) async {
    await _pumpScreen(
      tester,
      FakeUpdateService(checkResult: _availableResult()),
    );

    expect(find.byKey(const Key('update-screen-available')), findsOneWidget);
    expect(find.byKey(const Key('update-screen-latest-version')),
        findsOneWidget);
    expect(find.text('Wavely 1.0.0 → v1.0.1'), findsOneWidget);
    expect(find.text('Auto-update system'), findsOneWidget);
    expect(find.byKey(const Key('update-screen-update-now')), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
  });

  testWidgets('Update now streams progress, then the installer handoff',
      (tester) async {
    final gate = Completer<void>();
    final service = FakeUpdateService(
      checkResult: _availableResult(),
      gate: gate,
    );
    await _pumpScreen(tester, service);

    await tester.tap(find.byKey(const Key('update-screen-update-now')));
    await tester.pump(); // flush startInstall + progress emission

    expect(find.byKey(const Key('update-screen-progress')), findsOneWidget);
    expect(find.byKey(const Key('update-screen-progress-percent')),
        findsOneWidget);
    expect(find.text('1.0 / 1.0 MB (100%)'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('update-screen-done')), findsOneWidget);
    expect(find.text('Installer opened'), findsOneWidget);
  });

  testWidgets('failed install offers retry and the release page',
      (tester) async {
    await _pumpScreen(
      tester,
      FakeUpdateService(
        checkResult: _availableResult(),
        outcome: const InstallFailed('network lost'),
      ),
    );

    await tester.tap(find.byKey(const Key('update-screen-update-now')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('update-screen-error')), findsOneWidget);
    expect(find.text('Update did not complete'), findsOneWidget);
    expect(find.text('network lost'), findsOneWidget);
    expect(find.byKey(const Key('update-screen-retry')), findsOneWidget);
  });

  testWidgets('check failures render the error state with retry',
      (tester) async {
    await _pumpScreen(tester, ThrowingCheckService());

    expect(find.byKey(const Key('update-screen-error')), findsOneWidget);
    expect(find.byKey(const Key('update-screen-retry')), findsOneWidget);
  });

  testWidgets('no platform asset → button opens the release page instead',
      (tester) async {
    await _pumpScreen(
      tester,
      FakeUpdateService(
        checkResult: UpdateCheckResult.available(
          currentVersion: '1.0.0',
          latestVersion: 'v1.0.1',
          releaseUrl:
              'https://github.com/Dani-Devlop/Music_Wavely/releases/tag/v1.0.1',
        ),
      ),
    );

    expect(find.byKey(const Key('update-screen-available')), findsOneWidget);
    expect(find.text('Download from GitHub'), findsOneWidget);
    expect(
      find.textContaining('No installable asset'),
      findsOneWidget,
    );
  });
}

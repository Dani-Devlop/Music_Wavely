/// authored, awaiting local run.
///
/// Widget test of `SettingsScreen` in a minimal hermetic harness:
/// `MaterialApp` themed with the Wavely design system + `ProviderScope`
/// where ONLY the settings graph is overridden
/// (`sharedPrefsProvider.overrideWithValue` over mock SharedPreferences).
/// The cache-size row rides the io arm's failure degradation
/// (`getTemporaryDirectory` throws in tests -> 0 bytes), and the version row
/// rides the documented package-info fallback, so no plugin mocks are
/// needed. Verifies section headers render, toggles flip the notifier state
/// and persist, scan-folder rows render/remove, and the clear-cache flow
/// degrades to its friendly SnackBar.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/features/settings/domain/settings.dart';
import 'package:wavely/features/settings/presentation/settings_screen.dart';

String _key(String suffix) => '${AppConstants.settingsKeyPrefix}$suffix';

/// Scrolls the outer settings list until [finder] exists in the tree, then
/// centers it in the viewport (ListView children are built lazily, and
/// cacheExtent alone does not guarantee hittability).
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(
    finder,
    find.byType(ListView).first,
    const Offset(0, -250),
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

/// Makes the path_provider plugin deterministically ABSENT for the test.
///
/// A widget test runs in a fake-async zone: the reply of an UNMOCKED
/// platform channel is processed by the real event loop and never arrives,
/// so the degrade path would hang in loading forever. Replying null is the
/// in-zone equivalent of the plugin being absent (`invokeMethod` throws
/// MissingPluginException), which is exactly the contract under test.
void _mockPathProviderUnavailable() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async => null,
  );
}

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  Map<String, Object> initial = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPrefsProvider.overrideWithValue(prefs),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: WavelyThemes.dark(WavelyAccent.purple),
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('renders the documented section groups', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Playback'), findsOneWidget);
    // The lazy ListView builds below-the-fold sections on demand — scroll
    // to Storage before asserting (the group's existence is the contract,
    // not its first-viewport position).
    await _scrollTo(tester, find.text('Storage'));
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('GitHub'),
      find.byType(ListView).first,
      const Offset(0, -250),
    );
    await tester.pump();

    expect(find.text('More'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
  });

  testWidgets('cache-size row degrades to 0 MB without path_provider',
      (tester) async {
    _mockPathProviderUnavailable();
    await _pumpScreen(tester);

    await _scrollTo(tester, find.text('Cache size'));

    expect(find.text('0 MB'), findsOneWidget);
  });

  testWidgets('theme-mode segment flips state and persists', (tester) async {
    final ProviderContainer container = await _pumpScreen(tester);

    expect(container.read(settingsProvider).themeMode, ThemeMode.system);
    await tester.tap(find.text('Dark'));
    await tester.pump();

    expect(container.read(settingsProvider).themeMode, ThemeMode.dark);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_key('themeMode')), 'dark');
  });

  testWidgets('accent segment flips state and persists', (tester) async {
    final ProviderContainer container = await _pumpScreen(tester);

    await tester.tap(find.text('Green'));
    await tester.pump();

    expect(container.read(settingsProvider).accent, AccentColor.green);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_key('accent')), 'green');
  });

  testWidgets('reduce-transparency switch flips state and persists',
      (tester) async {
    final ProviderContainer container = await _pumpScreen(tester);

    await _scrollTo(tester, find.text('Reduce transparency'));
    await tester.tap(find.text('Reduce transparency'));
    await tester.pump();

    expect(container.read(settingsProvider).reduceTransparency, isTrue);
    expect(container.read(reduceTransparencyProvider), isTrue);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(_key('reduceTransparency')), isTrue);
  });

  testWidgets('gapless switch flips state and persists', (tester) async {
    final ProviderContainer container = await _pumpScreen(tester);

    await _scrollTo(tester, find.text('Gapless playback'));
    await tester.tap(find.text('Gapless playback'));
    await tester.pump();

    expect(container.read(settingsProvider).gaplessPlayback, isFalse);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(_key('gapless')), isFalse);
  });

  testWidgets('playback-speed slider persists a snapped value',
      (tester) async {
    final ProviderContainer container = await _pumpScreen(tester);

    // Sliders: crossfade first, playback speed second. Tapping the center
    // of the 0.5..2.0 slider with 6 divisions snaps to 1.25x.
    final Finder speedSlider = find.byType(Slider).at(1);
    await _scrollTo(tester, speedSlider);
    await tester.tap(speedSlider, warnIfMissed: false);
    await tester.pump();

    expect(container.read(settingsProvider).playbackSpeed, 1.25);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(_key('playbackSpeed')), 1.25);
  });

  testWidgets('seeded scan folders render and can be removed',
      (tester) async {
    final ProviderContainer container = await _pumpScreen(
      tester,
      initial: <String, Object>{
        _key('scanFolders'): <String>['/music/a', '/music/b'],
      },
    );

    await _scrollTo(tester, find.text('/music/a'));
    expect(find.text('/music/a'), findsOneWidget);
    expect(find.text('/music/b'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove folder').first);
    await tester.pump();

    expect(container.read(settingsProvider).scanFolders, <String>['/music/b']);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(_key('scanFolders')), <String>['/music/b']);
    expect(find.text('/music/a'), findsNothing);
  });

  testWidgets('clear-cache flow degrades to the friendly SnackBar',
      (tester) async {
    _mockPathProviderUnavailable();
    await _pumpScreen(tester);

    await _scrollTo(tester, find.text('Clear cache'));
    await tester.tap(find.text('Clear cache'));
    await tester.pumpAndSettle();

    expect(find.text('Clear cache?'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    // path_provider is unavailable in tests; both the temp dir and covers
    // cleanup degrade to zero removals per the io-arm contract.
    expect(find.text('Cache is already empty.'), findsOneWidget);
    // Let the SnackBar's auto-dismiss timer expire so the test ends
    // without pending timers.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}

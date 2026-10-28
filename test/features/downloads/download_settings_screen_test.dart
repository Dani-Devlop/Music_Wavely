// authored, awaiting local run.
//
// Widget tests for lib/features/downloads/presentation/download_settings_screen.dart:
// defaults render, quality segments persist, folder-template submit
// persists, Wi-Fi-only switch toggles, concurrency slider writes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/features/downloads/data/download_prefs.dart';
import 'package:wavely/features/downloads/data/downloads_providers.dart';
import 'package:wavely/features/downloads/presentation/download_settings_screen.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';

Future<ProviderContainer> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
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
      child: const MaterialApp(home: DownloadSettingsScreen()),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('renders defaults: original quality, template, wifi-only, 3',
      (WidgetTester tester) async {
    final ProviderContainer container = await _pump(tester);
    addTearDown(container.dispose);

    expect(find.text('Quality'), findsOneWidget);
    expect(find.text('Folder template'), findsOneWidget);
    expect(find.text('Storage location'), findsOneWidget);
    expect(find.byKey(const Key('folder-template-field')), findsOneWidget);
    expect(find.byKey(const Key('storage-location-field')), findsOneWidget);
    expect(find.byKey(const Key('wifi-only-switch')), findsOneWidget);
    expect(find.text('Concurrent downloads: 3'), findsOneWidget);
    // Wi-Fi-only defaults to on.
    final Switch wifi = tester.widget<Switch>(
      find.byKey(const Key('wifi-only-switch')),
    );
    expect(wifi.value, isTrue);
  });

  testWidgets('quality selection persists (flac)', (WidgetTester tester) async {
    final ProviderContainer container = await _pump(tester);

    await tester.tap(find.text('FLAC'));
    await tester.pump();

    final DownloadPrefs prefs = container.read(downloadPrefsProvider);
    expect(prefs.quality, 'flac');
  });

  testWidgets('folder template submit persists', (WidgetTester tester) async {
    final ProviderContainer container = await _pump(tester);

    await tester.enterText(
      find.byKey(const Key('folder-template-field')),
      'Music/{artist}/{album}',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    final DownloadPrefs prefs = container.read(downloadPrefsProvider);
    expect(prefs.folderTemplate, 'Music/{artist}/{album}');
  });

  testWidgets('storage location submit persists', (WidgetTester tester) async {
    final ProviderContainer container = await _pump(tester);

    await tester.enterText(
      find.byKey(const Key('storage-location-field')),
      '/storage/emulated/0/Wavely',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    final DownloadPrefs prefs = container.read(downloadPrefsProvider);
    expect(prefs.baseDir, '/storage/emulated/0/Wavely');
  });

  testWidgets('Wi-Fi-only switch toggles the pref', (WidgetTester tester) async {
    final ProviderContainer container = await _pump(tester);

    await tester.tap(find.byKey(const Key('wifi-only-switch')));
    await tester.pump();

    expect(container.read(downloadPrefsProvider).wifiOnly, isFalse);
  });

  testWidgets('concurrency slider writes the clamped value',
      (WidgetTester tester) async {
    final ProviderContainer container = await _pump(tester);

    // Slider 1..5 with 4 divisions: drag right by ~1/2 of the track → 3→5.
    final Rect rect = tester.getRect(
      find.byKey(const Key('concurrency-slider')),
    );
    await tester.dragFrom(
      rect.center,
      Offset(rect.width / 4, 0),
    );
    await tester.pump();

    final int value = container.read(downloadPrefsProvider).concurrency;
    expect(value, greaterThan(3));
    expect(value, lessThanOrEqualTo(5));
  });
}

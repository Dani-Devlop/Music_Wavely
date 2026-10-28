/// authored, awaiting local run.
///
/// Widget test of `FoldersTab` with the folder list served from a memory
/// `SettingsStore` (legacy JSON format written by `ScanFoldersStore`), a
/// fake `LibraryScanner` driving pickFolders/scan, and a memory Drift
/// database for the library count. Verifies rendering, the add-folder flow
/// (pick -> merge -> persist -> scan kick), the cancelled-pick no-op, the
/// remove flow and the rescan-all button.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/library/data/library_scanner.dart';
import 'package:wavely/features/library/data/library_scanner_provider.dart';
import 'package:wavely/features/library/presentation/folders_tab.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';

import 'fakes.dart';

const String _scanFoldersKey = 'wavely.settings.scanFolders';

Future<(ProviderContainer, FakeLibraryScanner)> _pumpTab(
  WidgetTester tester, {
  required FakeLibraryScanner scanner,
  required AppDatabase db,
  InMemorySettingsStore? store,
}) async {
  final InMemorySettingsStore effectiveStore =
      store ?? InMemorySettingsStore();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      settingsStoreProvider.overrideWithValue(effectiveStore),
      libraryScannerProvider.overrideWithValue(scanner),
      databaseProvider.overrideWithValue(db),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: WavelyThemes.dark(WavelyAccent.purple),
        home: const Scaffold(body: FoldersTab()),
      ),
    ),
  );
  // Bounded pumps instead of pumpAndSettle: the loading state renders a
  // repeating ShimmerBox, which would never settle on its own (the memory
  // store resolves within a frame, so two extra pumps are enough).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  return (container, scanner);
}

InMemorySettingsStore _storeWithFolders(List<String> folders) {
  final String json = folders
      .map((String f) => '"$f"')
      .join(',');
  return InMemorySettingsStore(
    initial: <String, Object>{_scanFoldersKey: '[$json]'},
  );
}

void main() {
  testWidgets('renders persisted folders with remove buttons',
      (tester) async {
    final AppDatabase db = newMemoryDb();
    addTearDown(db.close);

    await _pumpTab(
      tester,
      db: db,
      scanner: FakeLibraryScanner(),
      store: _storeWithFolders(<String>['/music/a', '/music/b']),
    );

    expect(find.text('Folders'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('folder-/music/a')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('folder-/music/b')),
        findsOneWidget);
    expect(find.byTooltip('Remove folder'), findsNWidgets(2));
    // Empty library -> the pointer empty state is rendered alongside.
    expect(find.text('No music yet'), findsOneWidget);
  });

  testWidgets('add-folder flow merges, persists and kicks a scan',
      (tester) async {
    final AppDatabase db = newMemoryDb();
    addTearDown(db.close);
    final InMemorySettingsStore store =
        _storeWithFolders(<String>['/music/a']);
    final FakeLibraryScanner scanner = FakeLibraryScanner(
      picked: <String>['/music/picked'],
      events: quietScanEvents('/music/a'),
    );

    final (ProviderContainer container, FakeLibraryScanner used) =
        await _pumpTab(tester, db: db, scanner: scanner, store: store);

    await tester.tap(find.text('Add folder'));
    await tester.pumpAndSettle();

    expect(find.text('/music/picked'), findsOneWidget);
    expect(find.text('/music/a'), findsOneWidget);
    expect(used.scanCalls, 1);
    expect(used.scannedFolders.single,
        <String>['/music/a', '/music/picked']);
    final Object? persisted = await store.read<List<String>>(_scanFoldersKey);
    // The canonical writer path serializes to a JSON string.
    final String? raw = await store.read<String>(_scanFoldersKey);
    expect(persisted, isNull, reason: 'ScanFoldersStore writes a JSON string');
    expect(raw, contains('/music/picked'));
    // Scan finished (completed event) -> UI is not stuck scanning.
    expect(container.read(scanStateProvider).scanning, isFalse);
  });

  testWidgets('cancelled folder pick changes nothing', (tester) async {
    final AppDatabase db = newMemoryDb();
    addTearDown(db.close);
    final InMemorySettingsStore store =
        _storeWithFolders(<String>['/music/a']);
    final FakeLibraryScanner scanner = FakeLibraryScanner();

    final (ProviderContainer _, FakeLibraryScanner used) = await _pumpTab(
      tester,
      db: db,
      scanner: scanner,
      store: store,
    );

    await tester.tap(find.text('Add folder'));
    await tester.pumpAndSettle();

    expect(find.text('/music/a'), findsOneWidget);
    expect(used.scanCalls, 0);
    expect(
      await store.read<String>(_scanFoldersKey),
      '["/music/a"]',
    );
  });

  testWidgets('remove-folder flow persists the shorter list', (tester) async {
    final AppDatabase db = newMemoryDb();
    addTearDown(db.close);
    final InMemorySettingsStore store =
        _storeWithFolders(<String>['/music/a', '/music/b']);
    final FakeLibraryScanner scanner = FakeLibraryScanner();

    final (ProviderContainer _, FakeLibraryScanner used) = await _pumpTab(
      tester,
      db: db,
      scanner: scanner,
      store: store,
    );

    await tester.tap(find.byTooltip('Remove folder').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('folder-/music/a')),
        findsNothing);
    expect(find.byKey(const ValueKey<String>('folder-/music/b')),
        findsOneWidget);
    expect(
      await store.read<String>(_scanFoldersKey),
      '["/music/b"]',
    );
    expect(used.scanCalls, 0, reason: 'removal must not start a scan');
  });

  testWidgets('rescan-all restarts a scan over the persisted folders',
      (tester) async {
    final AppDatabase db = newMemoryDb();
    addTearDown(db.close);
    final FakeLibraryScanner scanner = FakeLibraryScanner(
      events: quietScanEvents('/music/a'),
    );

    final (ProviderContainer _, FakeLibraryScanner used) = await _pumpTab(
      tester,
      db: db,
      scanner: scanner,
      store: _storeWithFolders(<String>['/music/a']),
    );

    expect(used.scanCalls, 0);
    await tester.tap(find.text('Rescan all'));
    await tester.pumpAndSettle();

    expect(used.scanCalls, 1);
    expect(used.scannedFolders.single, <String>['/music/a']);
  });
}

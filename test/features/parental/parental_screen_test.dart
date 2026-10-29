/// Authored, awaiting local run (Task 2-f).
///
/// Widget test of [ParentalScreen]'s PIN gate against a REAL in-memory
/// drift database seeded through [ParentalDao]: the gate renders when a
/// profile carries a pinHash (seeded with [hashPin] from lib), a wrong PIN
/// shakes and stays locked with no audit row, the correct PIN unlocks and
/// writes the `pin_unlocked` audit row (asserted via the DAO), and the
/// unlocked management UI renders its sections.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/parental/data/pin_hash.dart';
import 'package:wavely/features/parental/presentation/parental_screen.dart';

Future<AppDatabase> _pumpWithSeed(WidgetTester tester) async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.parentalDao.createProfile(name: 'Kid', pinHash: hashPin('2468'));
  await db.parentalDao.addWord(word: 'hell', severity: 'mild');
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        // settingsStoreProvider defaults to InMemorySettingsStore — good
        // enough for the screen; only the database needs overriding.
        databaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        // The PIN gate + cards read context.wavelyColors — pump the real
        // Wavely theme so the semantic extension is present.
        theme: WavelyThemes.dark(WavelyAccent.purple),
        home: const ParentalScreen(),
      ),
    ),
  );
  // First pump renders the loading spinner; the FutureProviders resolve in
  // microtasks and the next pumpAndSettle shows the gate.
  await tester.pump();
  await tester.pumpAndSettle();
  return db;
}

Future<void> _tapPin(WidgetTester tester, String digits) async {
  for (var i = 0; i < digits.length; i++) {
    await tester.tap(find.byKey(Key('pin-key-${digits[i]}')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('PIN gate appears when the profile has a pinHash',
      (tester) async {
    final db = await _pumpWithSeed(tester);
    addTearDown(db.close);
    expect(find.text('Enter PIN for Kid'), findsOneWidget);
    expect(find.byKey(const Key('pin-dot-0')), findsOneWidget);
    expect(find.byKey(const Key('pin-key-1')), findsOneWidget);
    expect(find.text('Profiles'), findsNothing); // still locked
  });

  testWidgets('a wrong PIN shakes and stays locked (no audit row)',
      (tester) async {
    final db = await _pumpWithSeed(tester);
    addTearDown(db.close);
    await _tapPin(tester, '1111'); // auto-verifies on the 4th digit
    // Gate is still up and the dots were cleared.
    expect(find.text('Enter PIN for Kid'), findsOneWidget);
    final dot = tester
        .widget<Container>(find.byKey(const Key('pin-dot-0')))
        .decoration! as BoxDecoration;
    // Cleared dot: the elevated fill, NOT the accent (locked + empty pin).
    expect(dot.color, isNot(AccentColors.purple.accent));
    final audit = await db.parentalDao.recentAudit();
    expect(
      audit.where((row) => row.event == 'pin_unlocked'),
      isEmpty,
    );
  });

  testWidgets('the correct PIN unlocks and writes the audit row',
      (tester) async {
    final db = await _pumpWithSeed(tester);
    addTearDown(db.close);
    await _tapPin(tester, '2468');
    // Unlocked management UI is now visible.
    expect(find.text('Profiles'), findsOneWidget);
    expect(find.text('Blocked words'), findsOneWidget);
    expect(find.text('hell'), findsOneWidget); // seeded word row
    // And the unlock was audited.
    final audit = await db.parentalDao.recentAudit();
    expect(
      audit.map((row) => row.event),
      contains('pin_unlocked'),
    );
  });

  testWidgets('unlock reveals the audit log section with the row',
      (tester) async {
    final db = await _pumpWithSeed(tester);
    addTearDown(db.close);
    await _tapPin(tester, '2468');
    await tester.pumpAndSettle();
    // The audit card is the LAST section of a lazy ListView — below the
    // fold and therefore not built until scrolled into the cache extent.
    await tester.scrollUntilVisible(
      find.text('Audit log'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Audit log'), findsOneWidget);
    expect(find.text('pin_unlocked'), findsOneWidget);
  });

  testWidgets('backspace removes the last entered digit', (tester) async {
    final db = await _pumpWithSeed(tester);
    addTearDown(db.close);
    await tester.tap(find.byKey(const Key('pin-key-2')));
    await tester.pump();
    final filled = tester
        .widget<Container>(find.byKey(const Key('pin-dot-0')))
        .decoration! as BoxDecoration;
    expect(filled.color, AccentColors.purple.accent);
    await tester.tap(find.byKey(const Key('pin-backspace')));
    await tester.pump();
    final cleared = tester
        .widget<Container>(find.byKey(const Key('pin-dot-0')))
        .decoration! as BoxDecoration;
    expect(cleared.color, isNot(AccentColors.purple.accent));
  });
}

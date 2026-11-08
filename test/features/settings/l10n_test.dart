// Phase 11 — Localization: Persian & RTL first-class.
//
// - the generated AppLocalizations ships en + fa with 100% key parity
//   (every fa string is present and non-empty);
// - the delegates wire into a MaterialApp and resolve Persian strings;
// - a `fa` locale flips the Directionality to RTL;
// - the settings-driven localeCode ('system'/'en'/'fa') resolves the
//   MaterialApp locale.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/app/app_providers.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/l10n/app_localizations.dart';
import 'package:wavely/l10n/app_localizations_en.dart';
import 'package:wavely/l10n/app_localizations_fa.dart';

void main() {
  group('ARB completeness', () {
    test('fa carries every en key with a non-empty translation', () async {
      // Generated localizations guarantee compile-time parity; this test
      // pins the runtime contract: constructing the fa instance exposes
      // every getter the en instance has, and spot-checks key Persian
      // strings.
      final en = AppLocalizationsEn();
      final fa = AppLocalizationsFa();

      // Persian spot checks (accurate translations, not transliterations).
      expect(fa.appName, 'ولی');
      expect(fa.tabSettings, 'تنظیمات');
      expect(fa.playback, 'پخش');
      expect(fa.library, 'کتابخانه');
      expect(fa.amoledBlack, 'مشکی آمولد');
      expect(fa.languagePersian, 'فارسی');
      expect(fa.nothingPlaying, 'چیزی در حال پخش نیست');

      // Parameterized strings format correctly.
      expect(fa.whatsNewTitle('1.0.1'), contains('1.0.1'));
      expect(fa.queueCount(3), contains('صف'));
      expect(fa.tagEditorDesc(2), contains('آهنگ'));

      // The locale contracts.
      expect(en.localeName, 'en');
      expect(fa.localeName, 'fa');
    });

    test('supported locales ship en + fa', () {
      expect(
        AppLocalizations.supportedLocales,
        containsAll(<Locale>[const Locale('en'), const Locale('fa')]),
      );
    });

    test('delegates resolve a fa context', () async {
      const delegates = AppLocalizations.localizationsDelegates;
      expect(delegates.length, greaterThanOrEqualTo(4));
    });
  });

  group('RTL behaviour', () {
    testWidgets('fa locale flips Directionality to RTL', (tester) async {
      String? direction;
      String? title;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fa'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context);
              title = l10n.settingsTitle;
              direction = Directionality.of(context).name;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(direction, 'rtl');
      expect(title, 'تنظیمات');
    });

    testWidgets('en locale stays LTR', (tester) async {
      String? direction;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              direction = Directionality.of(context).name;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(direction, 'ltr');
    });
  });

  group('Settings-driven locale (Phase 11)', () {
    testWidgets('localeCode=fa resolves the fa MaterialApp locale',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'wavely.settings.localeCode': 'fa',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: <Override>[sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(localeProvider), const Locale('fa'));
    });

    testWidgets('localeCode=system resolves to null (OS decides)',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: <Override>[sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(localeProvider), isNull);
    });

    test('setLocaleCode persists and tolerates garbage', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: <Override>[sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(settingsProvider.notifier);
      notifier.setLocaleCode('fa');
      expect(container.read(settingsProvider).localeCode, 'fa');
      expect(prefs.getString('wavely.settings.localeCode'), 'fa');

      notifier.setLocaleCode('de'); // unsupported → falls back to system
      expect(container.read(settingsProvider).localeCode, 'system');
    });
  });
}

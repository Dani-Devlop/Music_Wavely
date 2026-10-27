// authored, awaiting local run.
//
// Tests for lib/features/onboarding/data/onboarding_repository.dart and
// onboarding_state.dart over mock SharedPreferences: typed roundtrips
// (download quality, language priorities, region, AI consent), the tolerant
// completion flag reader, key-space contract, and OnboardingDraft defaults +
// mutation semantics.
//
// DELTA vs the task hint: OnboardingState is a PLAIN MUTABLE class
// (OnboardingDraft, deliberately no codegen — see the class doc), so the
// tests assert constructor defaults + in-place mutation instead of
// freezed copyWith.
library;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/features/onboarding/data/onboarding_repository.dart';
import 'package:wavely/features/onboarding/data/onboarding_state.dart';
import 'package:wavely/features/settings/domain/settings.dart';

void main() {
  group('OnboardingRepository roundtrips', () {
    test('download quality persists as an enum index and out-of-range '
        'indices fall back to q320', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repository = OnboardingRepository(prefs);

      expect(repository.readDownloadQuality(),
          OnboardingDownloadQuality.q320); // default when unset

      await repository.saveDownloadQuality(OnboardingDownloadQuality.flac);
      expect(prefs.getInt('wavely.onboarding.downloadQualityIndex'),
          OnboardingDownloadQuality.flac.index);
      expect(repository.readDownloadQuality(),
          OnboardingDownloadQuality.flac);

      await repository.saveDownloadQuality(OnboardingDownloadQuality.ask);
      expect(repository.readDownloadQuality(), OnboardingDownloadQuality.ask);

      // Corrupted/out-of-range payloads degrade to q320.
      await prefs.setInt('wavely.onboarding.downloadQualityIndex', 99);
      expect(repository.readDownloadQuality(),
          OnboardingDownloadQuality.q320);
      await prefs.setInt('wavely.onboarding.downloadQualityIndex', -1);
      expect(repository.readDownloadQuality(),
          OnboardingDownloadQuality.q320);
    });

    test('language priorities persist as a list and the saved list is a '
        'copy (later draft mutation cannot desync storage)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repository = OnboardingRepository(prefs);

      expect(repository.readLanguagePriorities(), isEmpty); // unset → empty

      final draftList = <String>['en', 'de'];
      await repository.saveLanguagePriorities(draftList);
      draftList.add('ja'); // mutate AFTER saving

      expect(repository.readLanguagePriorities(), <String>['en', 'de']);
    });

    test('saveRegion(null) removes the key; a code persists', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repository = OnboardingRepository(prefs);

      await repository.saveRegion('DE');
      expect(repository.readRegion(), 'DE');
      expect(prefs.getString('wavely.onboarding.region'), 'DE');

      await repository.saveRegion(null);
      expect(repository.readRegion(), isNull);
      expect(prefs.containsKey('wavely.onboarding.region'), isFalse);
    });

    test('AI consent defaults to false and roundtrips', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repository = OnboardingRepository(prefs);

      expect(repository.readAiConsent(), isFalse);

      await repository.saveAiConsent(true);
      expect(repository.readAiConsent(), isTrue);
      expect(prefs.getBool('wavely.onboarding.aiConsent'), isTrue);

      await repository.saveAiConsent(false);
      expect(repository.readAiConsent(), isFalse);
    });

    test('markCompleted writes the \'true\' string payload under the draft '
        'key and isCompleted reads it back', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repository = OnboardingRepository(prefs);

      expect(repository.isCompleted(), isFalse);

      await repository.markCompleted();

      expect(prefs.getString(OnboardingDraft.prefsCompletedKey), 'true');
      expect(repository.isCompleted(), isTrue);
    });

    test('isCompleted tolerates BOTH payloads the wizard may write: '
        'the bool true and the \'true\' string', () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{OnboardingDraft.prefsCompletedKey: true},
      );
      final boolPrefs = await SharedPreferences.getInstance();
      expect(OnboardingRepository(boolPrefs).isCompleted(), isTrue);

      SharedPreferences.setMockInitialValues(
        <String, Object>{OnboardingDraft.prefsCompletedKey: 'true'},
      );
      final stringPrefs = await SharedPreferences.getInstance();
      expect(OnboardingRepository(stringPrefs).isCompleted(), isTrue);

      SharedPreferences.setMockInitialValues(
        <String, Object>{OnboardingDraft.prefsCompletedKey: 'false'},
      );
      final junkPrefs = await SharedPreferences.getInstance();
      expect(OnboardingRepository(junkPrefs).isCompleted(), isFalse);
    });

    test('every onboarding key lives under the wavely.onboarding. prefix',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repository = OnboardingRepository(prefs);

      await repository.saveDownloadQuality(OnboardingDownloadQuality.flac);
      await repository.saveLanguagePriorities(<String>['en']);
      await repository.saveRegion('DE');
      await repository.saveAiConsent(true);
      await repository.markCompleted();

      final onboardingKeys = prefs
          .getKeys()
          .where((key) => key.startsWith('wavely.onboarding.'))
          .toSet();
      expect(onboardingKeys, <String>{
        'wavely.onboarding.downloadQualityIndex',
        'wavely.onboarding.languagePriorities',
        'wavely.onboarding.region',
        'wavely.onboarding.aiConsent',
        'wavely.onboarding.completed',
      });
      expect(prefs.getKeys().difference(onboardingKeys), isEmpty);
    });
  });

  group('OnboardingDraft', () {
    test('defaults mirror the accepted-all-defaults outcome', () {
      final draft = OnboardingDraft();

      expect(draft.themeMode, ThemeMode.system);
      expect(draft.accent, AccentColor.purple);
      expect(draft.region, isNull);
      expect(draft.languagePriorities, <String>['en']);
      expect(draft.neverPlayLanguages, isEmpty);
      expect(draft.downloadQuality, OnboardingDownloadQuality.q320);
      expect(draft.storageTemplate, '{artist}/{album}/{title}');
      expect(draft.parentalEnabled, isFalse);
      expect(draft.parentalPin, isNull);
      expect(draft.blockedSeedWords, isEmpty);
      expect(draft.aiConsent, isFalse);
      expect(draft.aiKeyHintShown, isFalse);
      expect(draft.scanFolders, isEmpty);
    });

    test('constructor seeds are copied into fresh mutable lists', () {
      final priorities = <String>['en', 'fa'];
      final folders = <String>['/music'];
      final draft = OnboardingDraft(
        languagePriorities: priorities,
        scanFolders: folders,
      );

      priorities.clear();
      folders.clear();

      expect(draft.languagePriorities, <String>['en', 'fa']);
      expect(draft.scanFolders, <String>['/music']);
    });

    test('fields mutate in place across the wizard pages (plain class, no '
        'codegen)', () {
      final draft = OnboardingDraft();

      draft.themeMode = ThemeMode.dark;
      draft.accent = AccentColor.green;
      draft.region = 'JP';
      draft.languagePriorities
        ..clear()
        ..addAll(<String>['ja', 'en']);
      draft.neverPlayLanguages.add('de');
      draft.downloadQuality = OnboardingDownloadQuality.flac;
      draft.parentalEnabled = true;
      draft.parentalPin = '1234';
      draft.blockedSeedWords.addAll(<String>['bad', 'words']);
      draft.aiConsent = true;
      draft.aiKeyHintShown = true;
      draft.scanFolders.add('/music/flac');

      expect(draft.themeMode, ThemeMode.dark);
      expect(draft.accent, AccentColor.green);
      expect(draft.region, 'JP');
      expect(draft.languagePriorities, <String>['ja', 'en']);
      expect(draft.neverPlayLanguages, <String>['de']);
      expect(draft.downloadQuality, OnboardingDownloadQuality.flac);
      expect(draft.parentalEnabled, isTrue);
      expect(draft.parentalPin, '1234');
      expect(draft.blockedSeedWords, <String>['bad', 'words']);
      expect(draft.aiConsent, isTrue);
      expect(draft.aiKeyHintShown, isTrue);
      expect(draft.scanFolders, <String>['/music/flac']);
    });

    test('prefsCompletedKey is the documented completion flag', () {
      expect(OnboardingDraft.prefsCompletedKey, 'wavely.onboarding.completed');
    });
  });

  group('kOnboardingLanguages', () {
    test('is the canonical 8-language const list', () {
      expect(
        kOnboardingLanguages,
        <String>['en', 'fa', 'es', 'fr', 'de', 'ar', 'hi', 'ja'],
      );
    });
  });
}

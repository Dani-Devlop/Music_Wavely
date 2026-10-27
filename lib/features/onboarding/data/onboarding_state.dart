import 'package:flutter/material.dart' show ThemeMode;

import 'package:wavely/features/settings/domain/settings.dart';

/// Language codes offered by the onboarding language-priority page (P4).
///
/// Deliberately a `const` list so both the wizard and the tests sort/toggle
/// against the same canonical set.
const List<String> kOnboardingLanguages = <String>[
  'en',
  'fa',
  'es',
  'fr',
  'de',
  'ar',
  'hi',
  'ja',
];

/// Download-quality preference collected by the onboarding wizard (P5).
///
/// Persisted under `wavely.onboarding.downloadQualityIndex` but only
/// consumed by the Stage 2.1 download pipeline — state-only until then.
enum OnboardingDownloadQuality {
  /// 320 kbps lossy download.
  q320,

  /// Lossless FLAC download.
  flac,

  /// Ask every time a download is prepared.
  ask,
}

/// Mutable state collected across the 10 onboarding pages.
///
/// Plain class on purpose (no codegen): the wizard mutates a single instance
/// while the user walks the pages and flushes it through the settings
/// notifier + [OnboardingRepository] when `Finish` is pressed (and only
/// then — backing out at the Done page persists nothing).
class OnboardingDraft {
  /// Creates a draft pre-filled with the same defaults as [AppSettings] so
  /// "user accepted every default" stays a valid outcome.
  ///
  /// List fields are copied into fresh mutable lists — the wizard mutates
  /// them in place (e.g. [languagePriorities] on reorder).
  OnboardingDraft({
    this.themeMode = ThemeMode.system,
    this.accent = AccentColor.purple,
    this.region,
    List<String>? languagePriorities,
    List<String>? neverPlayLanguages,
    this.downloadQuality = OnboardingDownloadQuality.q320,
    this.storageTemplate = '{artist}/{album}/{title}',
    this.parentalEnabled = false,
    this.parentalPin,
    List<String>? blockedSeedWords,
    this.aiConsent = false,
    this.aiKeyHintShown = false,
    List<String>? scanFolders,
  })  : languagePriorities =
            List<String>.of(languagePriorities ?? const <String>['en']),
        neverPlayLanguages =
            List<String>.of(neverPlayLanguages ?? const <String>[]),
        blockedSeedWords =
            List<String>.of(blockedSeedWords ?? const <String>[]),
        scanFolders = List<String>.of(scanFolders ?? const <String>[]);

  /// Prefs key marking onboarding completion (`'true'` string payload).
  ///
  /// Written ONLY by the Finish step; the router redirect reads it to skip
  /// the wizard on relaunch. `OnboardingRepository.isCompleted` is the
  /// tolerant reader (accepts bool payloads too).
  static const String prefsCompletedKey = 'wavely.onboarding.completed';

  /// Chosen appearance (persisted through the settings notifier on Finish).
  ThemeMode themeMode;

  /// Chosen accent (persisted through the settings notifier on Finish).
  AccentColor accent;

  /// Detected/edited country code (prefs-only field).
  String? region;

  /// Priority-ordered language codes (prefs-only field; consumed by the
  /// Stage 2 metadata/language engine).
  List<String> languagePriorities;

  /// Languages the player must never autoplay (persisted through the
  /// settings notifier — already consumed by later-stage engine features).
  List<String> neverPlayLanguages;

  /// Download-quality preference (prefs-only; stored for Stage 2.1).
  OnboardingDownloadQuality downloadQuality;

  /// Storage layout template with `{artist}/{album}/{title}` tokens
  /// (persisted through the settings notifier).
  String storageTemplate;

  /// Whether parental mode was enabled in P7.
  bool parentalEnabled;

  /// Raw 4-digit PIN collected in P7 (hashed before it ever touches disk).
  String? parentalPin;

  /// Starter blocked words parsed from the comma-separated P7 field.
  List<String> blockedSeedWords;

  /// Whether the user consented to AI features (prefs-only field).
  bool aiConsent;

  /// Whether the bring-your-own-key hint was displayed in P8 (UX flag; not
  /// persisted by the repository).
  bool aiKeyHintShown;

  /// Music folders picked in P9 (persisted through the settings notifier's
  /// scan-folder list — the scanner reads the same list after setup).
  List<String> scanFolders;
}

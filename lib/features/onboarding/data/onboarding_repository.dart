import 'package:shared_preferences/shared_preferences.dart';

import 'package:wavely/features/onboarding/data/onboarding_state.dart';

/// Loads/saves the onboarding-ONLY preference fields (typed).
///
/// Scope split:
/// - Appearance/scan/language settings go through the canonical settings
///   notifier (`wavely.settings.*` keys) — NOT this repository.
/// - Fields nobody else consumes yet (download quality, language
///   priorities, region, AI consent) plus the completion flag live under
///   the `wavely.onboarding.*` prefix handled here.
class OnboardingRepository {
  /// Binds the repository to the bootstrap [SharedPreferences] instance.
  const OnboardingRepository(this._prefs);

  static const String _prefix = 'wavely.onboarding.';
  static const String _keyQualityIndex = '${_prefix}downloadQualityIndex';
  static const String _keyLanguagePriorities = '${_prefix}languagePriorities';
  static const String _keyRegion = '${_prefix}region';
  static const String _keyAiConsent = '${_prefix}aiConsent';

  final SharedPreferences _prefs;

  /// Reads the persisted download quality; absent or out-of-range index
  /// falls back to [OnboardingDownloadQuality.q320].
  OnboardingDownloadQuality readDownloadQuality() {
    final index = _prefs.getInt(_keyQualityIndex);
    if (index == null ||
        index < 0 ||
        index >= OnboardingDownloadQuality.values.length) {
      return OnboardingDownloadQuality.q320;
    }
    return OnboardingDownloadQuality.values[index];
  }

  /// Persists [quality] as its enum index.
  Future<void> saveDownloadQuality(OnboardingDownloadQuality quality) =>
      _prefs.setInt(_keyQualityIndex, quality.index);

  /// Reads the persisted language priorities (empty when unset).
  List<String> readLanguagePriorities() =>
      _prefs.getStringList(_keyLanguagePriorities) ?? const <String>[];

  /// Persists [priorities] (copied so later mutation of the draft cannot
  /// desync the stored list).
  Future<void> saveLanguagePriorities(List<String> priorities) =>
      _prefs.setStringList(
        _keyLanguagePriorities,
        List<String>.of(priorities),
      );

  /// Reads the persisted region country code (null when unset).
  String? readRegion() => _prefs.getString(_keyRegion);

  /// Persists [region]; `null` removes the key.
  Future<void> saveRegion(String? region) => region == null
      ? _prefs.remove(_keyRegion)
      : _prefs.setString(_keyRegion, region);

  /// Reads the persisted AI consent (false when unset).
  bool readAiConsent() => _prefs.getBool(_keyAiConsent) ?? false;

  /// Persists [consent].
  Future<void> saveAiConsent(bool consent) =>
      _prefs.setBool(_keyAiConsent, consent);

  /// Synchronous completion check for the router redirect.
  ///
  /// Tolerant of both payloads the wizard may write: the bool `true` and
  /// the spec'd `'true'` string.
  bool isCompleted() {
    final raw = _prefs.get(OnboardingDraft.prefsCompletedKey);
    return raw == true || raw == 'true';
  }

  /// Marks onboarding complete (written once, by the Finish step).
  Future<void> markCompleted() =>
      _prefs.setString(OnboardingDraft.prefsCompletedKey, 'true');
}

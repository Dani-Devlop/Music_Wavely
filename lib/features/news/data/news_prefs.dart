import 'package:shared_preferences/shared_preferences.dart';

import 'package:wavely/features/news/data/news_category.dart';

/// News settings persisted in SharedPreferences (Stage 2.2).
///
/// Mirrors the [DownloadPrefs] pattern: a plain class over the shared
/// bootstrap `SharedPreferences` instance, no codegen, every getter has a
/// safe default so a fresh install renders the full feed.
class NewsPrefs {
  /// Creates prefs over [prefs].
  NewsPrefs(this._prefs);

  static const String _kCategories = 'news.categories';
  static const String _kCustomRss = 'news.customRss';
  static const String _kMutedSources = 'news.mutedSources';

  final SharedPreferences _prefs;

  /// Selected categories (chips/toggles). Empty list means "everything"
  /// — see [selectedOrAll] used by the screens.
  List<String> get selectedCategories =>
      _prefs.getStringList(_kCategories) ?? const <String>[];

  /// Custom RSS feed URLs added by the user (validated http/https only).
  List<String> get customRss =>
      _prefs.getStringList(_kCustomRss) ?? const <String>[];

  /// Muted source labels (e.g. `reddit/hiphopheads`) hidden from the feed.
  List<String> get mutedSources =>
      _prefs.getStringList(_kMutedSources) ?? const <String>[];

  /// Selected categories or, when nothing was ever selected, every
  /// category (first-run default).
  List<NewsCategory> get selectedOrAll {
    final List<String> stored = selectedCategories;
    if (stored.isEmpty) {
      return NewsCategory.values;
    }
    return stored
        .map(NewsCategory.tryParse)
        .whereType<NewsCategory>()
        .toList(growable: false);
  }

  /// Persists the selected category storage names (empty = all).
  Future<void> setSelectedCategories(List<NewsCategory> categories) =>
      _prefs.setStringList(
        _kCategories,
        categories.map((NewsCategory c) => c.storageName).toList(),
      );

  /// Persists the custom RSS list (caller validates).
  Future<void> setCustomRss(List<String> urls) =>
      _prefs.setStringList(_kCustomRss, urls);

  /// Persists the muted-source list.
  Future<void> setMutedSources(List<String> sources) =>
      _prefs.setStringList(_kMutedSources, sources);
}

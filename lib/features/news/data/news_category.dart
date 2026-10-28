/// News category taxonomy + keyword classifier (Stage 2.2).
///
/// Pure Dart and fully testable: [NewsCategoryClassifier.classify] runs a
/// case-insensitive keyword scan over the title+summary pair and falls back
/// to [NewsCategory.artistNews] when nothing matches. Keyword lists are
/// intentionally small and static — no network, no ML.
library;

/// Editorial categories of the in-app news feed.
enum NewsCategory {
  /// AI / machine learning / plugins / synthesizers.
  techAi,

  /// How-tos, tutorials, learning material.
  education,

  /// Mixing, mastering, DAW and studio production.
  production,

  /// Album / single / EP announcements.
  newReleases,

  /// Everything else (default bucket).
  artistNews;

  /// Stable label used in prefs persistence and the DB JSON column.
  String get storageName {
    switch (this) {
      case NewsCategory.techAi:
        return 'tech_ai';
      case NewsCategory.education:
        return 'education';
      case NewsCategory.production:
        return 'production';
      case NewsCategory.newReleases:
        return 'new_releases';
      case NewsCategory.artistNews:
        return 'artist_news';
    }
  }

  /// Human label for chips and toggles.
  String get label {
    switch (this) {
      case NewsCategory.techAi:
        return 'Tech & AI';
      case NewsCategory.education:
        return 'Education';
      case NewsCategory.production:
        return 'Production';
      case NewsCategory.newReleases:
        return 'New releases';
      case NewsCategory.artistNews:
        return 'Artist news';
    }
  }

  /// Parses a persisted storage name; unknown names return `null`.
  static NewsCategory? tryParse(String name) {
    for (final NewsCategory category in NewsCategory.values) {
      if (category.storageName == name) {
        return category;
      }
    }
    return null;
  }
}

/// Keyword classifier over title/summary text.
abstract final class NewsCategoryClassifier {
  /// Ordered rules: the FIRST matching bucket wins, so more specific
  /// buckets are checked before [NewsCategory.artistNews] (the default).
  static const Map<NewsCategory, List<String>> _rules =
      <NewsCategory, List<String>>{
    NewsCategory.techAi: <String>[
      'ai',
      'machine learning',
      'synthesizer',
      'synth plugin',
      'plugin',
    ],
    NewsCategory.education: <String>[
      'how to',
      'tutorial',
      'learn',
      'guide',
    ],
    NewsCategory.production: <String>[
      'mixing',
      'mastering',
      'production',
      'daw',
    ],
    NewsCategory.newReleases: <String>[
      'album',
      'single',
      'drops',
    ],
  };

  /// Classifies the combined [title] + [summary] text. Case-insensitive;
  /// word-boundary aware for single-token keywords (`ai`, `ep`, `daw`) so
  /// "said" does not match `ai`, while multi-word phrases stay substring
  /// matches. Returns [NewsCategory.artistNews] when nothing matches.
  static NewsCategory classify(String title, String summary) {
    final String haystack =
        '${title.trim()} ${summary.trim()}'.toLowerCase();
    if (haystack.trim().isEmpty) {
      return NewsCategory.artistNews;
    }
    final List<String> words = haystack.split(RegExp(r'[^a-z0-9+#]+'));
    for (final MapEntry<NewsCategory, List<String>> rule
        in _rules.entries) {
      for (final String keyword in rule.value) {
        if (keyword.contains(' ')) {
          // Multi-word phrase: plain substring match is safe because both
          // sides are already lowercased and the haystack keeps its spaces.
          if (haystack.contains(keyword)) {
            return rule.key;
          }
        } else if (words.contains(keyword)) {
          return rule.key;
        }
      }
    }
    return NewsCategory.artistNews;
  }
}

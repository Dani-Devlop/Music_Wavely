/// Authored, awaiting local run (Stage 3 audit — coverage gap).
///
/// [NewsCategoryClassifier] and the [NewsCategory] taxonomy contract:
/// ordered rules, word-boundary behaviour for single-token keywords,
/// substring behaviour for multi-word phrases, case-insensitivity, the
/// `artistNews` default, and the storage-name round trip.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/news/data/news_category.dart';

void main() {
  group('NewsCategoryClassifier.classify', () {
    test('tech_ai wins on the most specific single-token rules', () {
      expect(
        NewsCategoryClassifier.classify(
          'New AI synthesizer plugin ships',
          '',
        ),
        NewsCategory.techAi,
      );
    });

    test('tech_ai matches multi-word phrases as substrings', () {
      expect(
        NewsCategoryClassifier.classify(
          'The quiet rise of machine learning in studios',
          '',
        ),
        NewsCategory.techAi,
      );
    });

    test('word boundaries: "said" does not trigger the ai rule', () {
      expect(
        NewsCategoryClassifier.classify(
          'They said the tour was the best of the year',
          '',
        ),
        NewsCategory.artistNews,
      );
    });

    test('education wins over production because it is checked first', () {
      // 'how to' (education) and 'mixing' (production) both match; the
      // ordered-rules contract says the FIRST bucket wins.
      expect(
        NewsCategoryClassifier.classify(
          'How to approach mixing your first record',
          '',
        ),
        NewsCategory.education,
      );
    });

    test('production matches mixing/mastering/daw tokens', () {
      expect(
        NewsCategoryClassifier.classify('Mastering tips for your DAW', ''),
        NewsCategory.production,
      );
      expect(
        NewsCategoryClassifier.classify('Mixing a live record', ''),
        NewsCategory.production,
      );
    });

    test('new_releases matches album/single/drops', () {
      expect(
        NewsCategoryClassifier.classify('New album drops Friday', ''),
        NewsCategory.newReleases,
      );
      expect(
        NewsCategoryClassifier.classify('Debut single out now', ''),
        NewsCategory.newReleases,
      );
    });

    test('falls back to artist_news when nothing matches', () {
      expect(
        NewsCategoryClassifier.classify('Artist wins lifetime award', ''),
        NewsCategory.artistNews,
      );
    });

    test('empty input falls back to artist_news', () {
      expect(
        NewsCategoryClassifier.classify('   ', ''),
        NewsCategory.artistNews,
      );
    });

    test('classification is case-insensitive', () {
      expect(
        NewsCategoryClassifier.classify('PLUGIN OF THE YEAR', ''),
        NewsCategory.techAi,
      );
    });

    test('title and summary are scanned together', () {
      expect(
        NewsCategoryClassifier.classify(
          'Studio visit',
          'a hands-on tutorial for tape saturation',
        ),
        NewsCategory.education,
      );
    });

    test('plural tokens are not matched by single-token rules', () {
      // Documents the exact-token semantics: 'plugins' ≠ 'plugin'.
      expect(
        NewsCategoryClassifier.classify('Best plugins of the year', ''),
        NewsCategory.artistNews,
      );
    });
  });

  group('NewsCategory taxonomy', () {
    test('storage names round-trip through tryParse for every value', () {
      for (final NewsCategory category in NewsCategory.values) {
        expect(NewsCategory.tryParse(category.storageName), category);
      }
    });

    test('storage names are the stable snake_case contract', () {
      expect(NewsCategory.techAi.storageName, 'tech_ai');
      expect(NewsCategory.education.storageName, 'education');
      expect(NewsCategory.production.storageName, 'production');
      expect(NewsCategory.newReleases.storageName, 'new_releases');
      expect(NewsCategory.artistNews.storageName, 'artist_news');
    });

    test('tryParse returns null for unknown names', () {
      expect(NewsCategory.tryParse('unknown_bucket'), isNull);
      expect(NewsCategory.tryParse(''), isNull);
      expect(NewsCategory.tryParse('TECH_AI'), isNull); // case-sensitive
    });

    test('labels are non-empty and unique', () {
      final labels = NewsCategory.values.map((c) => c.label).toList();
      expect(labels.every((l) => l.trim().isNotEmpty), isTrue);
      expect(labels.toSet().length, labels.length);
    });
  });
}

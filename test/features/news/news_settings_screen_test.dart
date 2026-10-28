// authored, awaiting local run.
//
// Widget tests for the News settings screen: category toggles persist,
// custom RSS validation (bad/non-http rejected, good added), feed removal
// and muted-source unmute.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/news/data/news_category.dart';
import 'package:wavely/features/news/data/news_prefs.dart';
import 'package:wavely/features/news/data/news_providers.dart';
import 'package:wavely/features/news/presentation/news_settings_screen.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, Object> initial = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPrefsProvider.overrideWithValue(prefs),
      newsPrefsProvider.overrideWithValue(NewsPrefs(prefs)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: WavelyThemes.dark(WavelyAccent.purple),
        home: const NewsSettingsScreen(),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('category toggle persists to prefs', (tester) async {
    final container = await _pump(tester);

    await tester.tap(find.byKey(const ValueKey<String>('news-toggle-tech_ai')));
    await tester.pump();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('news.categories'),
      contains('tech_ai'),
    );
    expect(
      container.read(newsPrefsProvider).selectedCategories,
      contains('tech_ai'),
    );
  });

  testWidgets('good https RSS URL is added and persisted', (tester) async {
    final container = await _pump(tester);

    await tester.enterText(
      find.byKey(const Key('news-rss-field')),
      'https://example.com/feed.xml',
    );
    await tester.tap(find.byKey(const Key('news-rss-add')));
    await tester.pump();

    expect(
      container.read(newsPrefsProvider).customRss,
      <String>['https://example.com/feed.xml'],
    );
    expect(find.byKey(const ValueKey<String>('news-rss-https://example.com/feed.xml')),
        findsOneWidget);
  });

  testWidgets('non-http scheme is rejected with a SnackBar', (tester) async {
    await _pump(tester);

    await tester.enterText(
      find.byKey(const Key('news-rss-field')),
      'ftp://example.com/feed.xml',
    );
    await tester.tap(find.byKey(const Key('news-rss-add')));
    await tester.pump();

    expect(
      find.text('Only http(s) feed URLs are supported.'),
      findsOneWidget,
    );
  });

  testWidgets('garbage input is rejected as an invalid URL', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byKey(const Key('news-rss-field')), 'not a url');
    await tester.tap(find.byKey(const Key('news-rss-add')));
    await tester.pump();

    expect(
      find.text('That does not look like a valid URL.'),
      findsOneWidget,
    );
  });

  testWidgets('added feeds can be removed', (tester) async {
    final container = await _pump(
      tester,
      initial: const <String, Object>{
        'news.customRss': <String>['https://a.example/f.xml'],
      },
    );
    final Finder row =
        find.byKey(const ValueKey<String>('news-rss-https://a.example/f.xml'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove feed'));
    await tester.pump();

    expect(container.read(newsPrefsProvider).customRss, isEmpty);
  });

  testWidgets('muted sources render and can be unmuted', (tester) async {
    final container = await _pump(
      tester,
      initial: const <String, Object>{
        'news.mutedSources': <String>['reddit/Music'],
      },
    );
    final Finder row =
        find.byKey(const ValueKey<String>('news-muted-reddit/Music'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unmute'));
    await tester.pump();

    expect(container.read(newsPrefsProvider).mutedSources, isEmpty);
  });

  test('validateRssUrl accepts http(s) and rejects the rest', () {
    expect(validateRssUrl('https://ok.example/f'), isNull);
    expect(validateRssUrl('http://ok.example/f'), isNull);
    expect(validateRssUrl(''), isNotNull);
    expect(validateRssUrl('no scheme'), isNotNull);
    expect(validateRssUrl('javascript:alert(1)'), isNotNull);
    expect(validateRssUrl('mailto:x@y.z'), isNotNull);
  });

  test('NewsCategory.tryParse round-trips every storage name', () {
    for (final NewsCategory category in NewsCategory.values) {
      expect(NewsCategory.tryParse(category.storageName), category);
    }
    expect(NewsCategory.tryParse('unknown'), isNull);
  });
}

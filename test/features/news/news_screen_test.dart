// authored, awaiting local run.
//
// Widget tests for the News screen: loading shimmer, loaded list, empty
// state with settings CTA, error state, and category-chip toggling.

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/core/utils/link_launcher.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/remote/metadata_http.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/news/data/news_article.dart';
import 'package:wavely/features/news/data/news_category.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/features/news/data/news_prefs.dart';
import 'package:wavely/features/news/data/news_providers.dart';
import 'package:wavely/features/news/data/news_service.dart';
import 'package:wavely/features/news/presentation/news_screen.dart';
import 'package:wavely/features/news/presentation/news_settings_screen.dart';

class _NoopClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw UnimplementedError('noop client must not be used');
  }
}

NewsArticle _article(String id, {String source = 'reddit/Music'}) =>
    NewsArticle(
      source: source,
      sourceId: id,
      title: 'Article $id title',
      summary: 'Summary for $id',
      url: 'https://example.com/$id',
      publishedAt: DateTime.utc(2026, 3, 1),
      fetchedAt: DateTime.utc(2026, 3, 1),
      categories: const <NewsCategory>[NewsCategory.artistNews],
    );

/// Scripted [NewsService] with canned getArticles results.
class _FakeNewsService extends NewsService {
  _FakeNewsService(AppDatabase db, NewsPrefs prefs)
      : super(
          dao: db.newsDao,
          prefs: prefs,
          http: CachingHttpClient(
            cacheDao: db.httpCacheDao,
            client: _NoopClient(),
          ),
        );

  List<NewsArticle> result = <NewsArticle>[];
  List<NewsCategory>? lastCategories;
  bool shouldThrow = false;
  Completer<List<NewsArticle>>? gate;

  @override
  Future<List<NewsArticle>> getArticles({
    required List<NewsCategory> categories,
    int limit = 30,
  }) async {
    lastCategories = categories;
    if (shouldThrow) {
      throw StateError('service unavailable');
    }
    if (gate != null) {
      await gate!.future;
    }
    return result;
  }
}

class _RecordingLinkLauncher implements LinkLauncher {
  final List<Uri> launched = <Uri>[];

  @override
  Future<bool> launchExternal(Uri url) async {
    launched.add(url);
    return true;
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _FakeNewsService service,
  _RecordingLinkLauncher launcher,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPrefsProvider.overrideWithValue(prefs),
      newsPrefsProvider.overrideWithValue(NewsPrefs(prefs)),
      newsServiceProvider.overrideWith((ref) async => service),
      linkLauncherProvider.overrideWithValue(launcher),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: WavelyThemes.dark(WavelyAccent.purple),
        home: const NewsScreen(),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('loading state renders shimmer placeholders',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final prefs = await _prefsInstance();
    final service = _FakeNewsService(db, prefs)
      ..gate = Completer<List<NewsArticle>>();
    await _pump(tester, service, _RecordingLinkLauncher());
    await tester.pump();
    // The gated service never resolves: the shimmer keeps rendering.
    expect(find.byType(ShimmerBox), findsWidgets);
  });

  testWidgets('loaded state renders article cards and rows', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final prefs = await _prefsInstance();
    final service = _FakeNewsService(db, prefs)
      ..result = <NewsArticle>[
        _article('a1'),
        _article('a2', source: 'pitchfork'),
      ];
    final launcher = _RecordingLinkLauncher();
    await _pump(tester, service, launcher);
    await tester.pumpAndSettle();

    expect(find.text('Article a1 title'), findsOneWidget);
    expect(find.text('Article a2 title'), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);
    expect(service.lastCategories, isNotNull);
  });

  testWidgets('tapping an article opens it via the LinkLauncher',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final prefs = await _prefsInstance();
    final service = _FakeNewsService(db, prefs)
      ..result = <NewsArticle>[_article('tap-1')];
    final launcher = _RecordingLinkLauncher();
    await _pump(tester, service, launcher);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Article tap-1 title'));
    await tester.pump();
    expect(launcher.launched.single.toString(), 'https://example.com/tap-1');
  });

  testWidgets('empty state shows the settings CTA', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final prefs = await _prefsInstance();
    final service = _FakeNewsService(db, prefs)..result = <NewsArticle>[];
    await _pump(tester, service, _RecordingLinkLauncher());
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.byKey(const Key('news-open-settings-cta')), findsOneWidget);
  });

  testWidgets('error state shows the offline empty state + CTA',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final prefs = await _prefsInstance();
    final service = _FakeNewsService(db, prefs)..shouldThrow = true;
    await _pump(tester, service, _RecordingLinkLauncher());
    await tester.pumpAndSettle();

    expect(find.text('News is unavailable right now'), findsOneWidget);
    expect(find.byKey(const Key('news-open-settings-cta')), findsOneWidget);
  });

  testWidgets('toggling a chip off filters the next load', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final prefs = await _prefsInstance();
    final service = _FakeNewsService(db, prefs)
      ..result = <NewsArticle>[_article('x')];
    await _pump(tester, service, _RecordingLinkLauncher());
    await tester.pumpAndSettle();

    // Chip for tech_ai starts selected (all categories by default).
    final Finder chip = find.byKey(const ValueKey<String>('news-chip-tech_ai'));
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();

    // After the toggle the selected set no longer contains tech_ai.
    final List<NewsCategory> sent = service.lastCategories!;
    expect(sent.contains(NewsCategory.techAi), isFalse);
  });
}

Future<NewsPrefs> _prefsInstance() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return NewsPrefs(await SharedPreferences.getInstance());
}

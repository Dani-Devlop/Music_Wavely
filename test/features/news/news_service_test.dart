// authored, awaiting local run.
//
// Tests for lib/features/news/data/news_service.dart + the classifier:
// keyword classification (15 cases), Reddit JSON parse, RSS parses
// (pitchfork/nme fixtures), HTTP-cache TTL behaviour, offline fallback to
// stored rows, muted sources, custom RSS and category filtering.

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/remote/metadata_http.dart';
import 'package:wavely/features/news/data/news_article.dart';
import 'package:wavely/features/news/data/news_category.dart';
import 'package:wavely/features/news/data/news_prefs.dart';
import 'package:wavely/features/news/data/news_service.dart';

AppDatabase _db() => AppDatabase(NativeDatabase.memory());

String _fixture(String name) =>
    File('test/fixtures/news/$name').readAsStringSync();

Future<NewsPrefs> _prefs({List<String> muted = const <String>[]}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'news.mutedSources': muted,
  });
  return NewsPrefs(await SharedPreferences.getInstance());
}

/// In-memory HTTP client serving canned bodies per URL; counts requests.
class _FakeHttp extends http_testing.MockClient {
  _FakeHttp._(
    Future<http.Response> Function(http.Request) handler, {
    required this.status,
  }) : super(handler);

  /// Factory keeps the handler in a local `self` reference: initializers
  /// cannot touch `this`, constructor bodies can (through the local).
  factory _FakeHttp(Map<String, String> bodies, {int status = 200}) {
    late final _FakeHttp self;
    self = _FakeHttp._(
      (request) async {
        self.calls++;
        final String? body = bodies[request.url.toString()];
        if (body == null) {
          return http.Response('not found', 404);
        }
        return http.Response(body, status);
      },
      status: status,
    );
    return self;
  }

  int calls = 0;
  final int status;
}

const String _redditUrl =
    'https://www.reddit.com/r/Music/new.json?limit=50';

void main() {
  group('NewsCategoryClassifier (15 cases)', () {
    NewsCategory c(String title, [String summary = '']) =>
        NewsCategoryClassifier.classify(title, summary);

    // -- tech_ai (4) --
    test('1: "AI" word match -> techAi', () =>
        expect(c('This AI writes hit songs'), NewsCategory.techAi));
    test('2: "machine learning" phrase -> techAi', () => expect(
        c('Machine learning reshapes radio'), NewsCategory.techAi));
    test('3: "synthesizer" -> techAi', () => expect(
        c('The modular synthesizer revival'), NewsCategory.techAi));
    test('4: "plugin" -> techAi', () =>
        expect(c('Free plugin round-up', 'best plugins'),
            NewsCategory.techAi));

    // -- education (3) --
    test('5: "how to" phrase -> education', () =>
        expect(c('How to build a home studio'), NewsCategory.education));
    test('6: "tutorial" -> education', () =>
        expect(c('A tutorial for sidechain compression'),
            NewsCategory.education));
    test('7: "guide" -> education', () =>
        expect(c('The beginner guide to synths'), NewsCategory.education));

    // -- production (3) --
    test('8: "mixing" -> production', () =>
        expect(c('Mixing secrets from pro engineers'),
            NewsCategory.production));
    test('9: "mastering" -> production', () =>
        expect(c('Mastering on a budget'), NewsCategory.production));
    test('10: "daw" word match -> production', () =>
        expect(c('Your DAW is lying to you'), NewsCategory.production));

    // -- new_releases (3) --
    test('11: "album" -> newReleases', () =>
        expect(c('Aurora announces new album'), NewsCategory.newReleases));
    test('12: "single" -> newReleases', () =>
        expect(c('Debut single arrives Friday'), NewsCategory.newReleases));
    test('13: "ep" word match -> newReleases', () =>
        expect(c('New EP drops tonight', 'the EP arrives'),
            NewsCategory.newReleases));

    // -- artist_news default (2) --
    test('14: no keyword -> artistNews', () =>
        expect(c('Farewell tour announced for autumn'),
            NewsCategory.artistNews));
    test('15: empty text -> artistNews', () =>
        expect(NewsCategoryClassifier.classify('', ''),
            NewsCategory.artistNews));
  });

  test('word-boundary: "said" does NOT match tech_ai "ai"', () {
    expect(
      NewsCategoryClassifier.classify('Chairman said tour is over', ''),
      NewsCategory.artistNews,
    );
  });

  group('Reddit JSON parse', () {
    test('parses fixture children into articles', () {
      final List<NewsArticle> articles = NewsService.parseReddit(
        'reddit/Music',
        _fixture('reddit_music.json'),
        DateTime.utc(2026),
      );
      expect(articles, hasLength(3));
      expect(articles.first.sourceId, '1abcde');
      expect(articles.first.title, contains('AI mastering plugin'));
      expect(articles.first.url, 'https://example.com/ai-mastering');
      expect(articles.first.imageUrl, isNotNull);
      expect(
        articles.first.publishedAt,
        DateTime.fromMillisecondsSinceEpoch(
          (1767139200.0 * 1000).round(),
          isUtc: true,
        ),
      );
      expect(articles.first.categories, contains(NewsCategory.techAi));
      // Self-post fallback summary mentions the subreddit.
      expect(articles[1].summary, contains('r/Music'));
      expect(articles[1].categories, contains(NewsCategory.newReleases));
    });

    test('malformed JSON degrades to empty list', () {
      final List<NewsArticle> articles = NewsService.parseReddit(
        'reddit/Music',
        'not-json',
        DateTime.utc(2026),
      );
      expect(articles, isEmpty);
    });
  });

  group('RSS parse', () {
    test('pitchfork fixture: cdata strip, guid id, media thumbnail', () {
      final List<NewsArticle> articles = NewsService.parseRss(
        'pitchfork',
        _fixture('pitchfork.rss'),
        DateTime.utc(2026),
      );
      expect(articles, hasLength(2));
      expect(articles.first.sourceId, 'pf-001');
      expect(articles.first.title, contains('synthesizer'));
      expect(articles.first.summary, contains('compilation'));
      expect(articles.first.summary, isNot(contains('<b>')));
      expect(articles.first.imageUrl, 'https://pitchfork.com/img/pf-001.jpg');
      expect(
        articles.first.publishedAt,
        DateTime.utc(2025, 1, 6, 10, 30),
      );
      expect(articles.first.categories, contains(NewsCategory.techAi));
      expect(articles[1].categories, contains(NewsCategory.newReleases));
    });

    test('nme fixture: enclosure image + rfc822 date', () {
      final List<NewsArticle> articles = NewsService.parseRss(
        'nme',
        _fixture('nme.rss'),
        DateTime.utc(2026),
      );
      expect(articles, hasLength(2));
      expect(articles.first.imageUrl, 'https://www.nme.com/img/studio.jpg');
      expect(articles.first.publishedAt, DateTime.utc(2026, 2, 8, 14));
      expect(articles.first.categories, contains(NewsCategory.education));
      expect(articles[1].categories, NewsCategory.artistNews);
    });
  });

  group('NewsService over fake HTTP + in-memory db', () {
    test('serves the reddit fixture through the feed list', () async {
      final db = _db();
      addTearDown(db.close);
      final fake = _FakeHttp(<String, String>{
        _redditUrl: _fixture('reddit_music.json'),
      });
      final service = NewsService(
        dao: db.newsDao,
        prefs: await _prefs(),
        http: CachingHttpClient(cacheDao: db.httpCacheDao, client: fake),
        feeds: <NewsFeed>[NewsFeed.reddit('Music')],
        now: () => DateTime.utc(2026, 3, 1),
      );
      final List<NewsArticle> result = await service.getArticles(
        categories: NewsCategory.values,
        limit: 10,
      );
      expect(result, hasLength(3));
      expect(fake.calls, 1);
      // Persisted for offline reads.
      expect(await db.newsDao.allStored(), hasLength(3));
    });

    test('cache TTL: second call within 30 min does not hit the network',
        () async {
      final db = _db();
      addTearDown(db.close);
      final fake = _FakeHttp(<String, String>{
        _redditUrl: _fixture('reddit_music.json'),
      });
      var clock = DateTime.utc(2026, 3, 1, 12);
      final service = NewsService(
        dao: db.newsDao,
        prefs: await _prefs(),
        http: CachingHttpClient(cacheDao: db.httpCacheDao, client: fake),
        feeds: <NewsFeed>[NewsFeed.reddit('Music')],
        now: () => clock,
      );
      await service.getArticles(categories: NewsCategory.values);
      expect(fake.calls, 1);
      clock = clock.add(const Duration(minutes: 5));
      await service.getArticles(categories: NewsCategory.values);
      expect(fake.calls, 1, reason: 'fresh cache short-circuits the feed');
    });

    test('offline fallback: dead feed + stored rows still serve articles',
        () async {
      final db = _db();
      addTearDown(db.close);
      final fake = _FakeHttp(<String, String>{}, status: 500);
      final service = NewsService(
        dao: db.newsDao,
        prefs: await _prefs(),
        http: CachingHttpClient(cacheDao: db.httpCacheDao, client: fake),
        feeds: <NewsFeed>[NewsFeed.reddit('Music')],
        now: () => DateTime.utc(2026, 3, 1),
      );
      // Seed the offline store directly.
      await db.newsDao.upsertAll(<NewsArticlesCompanion>[
        NewsArticle(
          source: 'reddit/Music',
          sourceId: 'seed-1',
          title: 'Stored album announcement',
          summary: 'An album arrives.',
          url: 'https://example.com/stored',
          publishedAt: DateTime.utc(2026, 2, 28),
          fetchedAt: DateTime.utc(2026, 2, 28),
          categories: const <NewsCategory>[NewsCategory.newReleases],
        ).toCompanion(),
      ]);
      final List<NewsArticle> result = await service.getArticles(
        categories: NewsCategory.values,
      );
      expect(result, hasLength(1));
      expect(result.single.sourceId, 'seed-1');
      expect(fake.calls, 1, reason: 'the 500 response was attempted once');
    });

    test('muted sources are filtered out', () async {
      final db = _db();
      addTearDown(db.close);
      final service = NewsService(
        dao: db.newsDao,
        prefs: await _prefs(muted: <String>['reddit/Music']),
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: _FakeHttp(<String, String>{
            _redditUrl: _fixture('reddit_music.json'),
          }),
        ),
        feeds: <NewsFeed>[NewsFeed.reddit('Music')],
        now: () => DateTime.utc(2026, 3, 1),
      );
      final List<NewsArticle> result = await service.getArticles(
        categories: NewsCategory.values,
      );
      expect(result, isEmpty);
    });

    test('custom RSS feeds are fetched alongside built-ins', () async {
      final db = _db();
      addTearDown(db.close);
      final fake = _FakeHttp(<String, String>{
        'https://custom.example/feed.xml': _fixture('nme.rss'),
      });
      final service = NewsService(
        dao: db.newsDao,
        prefs: await _prefs(),
        http: CachingHttpClient(cacheDao: db.httpCacheDao, client: fake),
        feeds: <NewsFeed>[
          NewsFeed.rss(
            'custom.example',
            Uri.https('custom.example', '/feed.xml'),
          ),
        ],
        now: () => DateTime.utc(2026, 3, 1),
      );
      final List<NewsArticle> result = await service.getArticles(
        categories: NewsCategory.values,
      );
      expect(result, hasLength(2));
      expect(result.every((a) => a.source == 'custom.example'), isTrue);
    });

    test('category filter narrows results', () async {
      final db = _db();
      addTearDown(db.close);
      final service = NewsService(
        dao: db.newsDao,
        prefs: await _prefs(),
        http: CachingHttpClient(
          cacheDao: db.httpCacheDao,
          client: _FakeHttp(<String, String>{
            _redditUrl: _fixture('reddit_music.json'),
          }),
        ),
        feeds: <NewsFeed>[NewsFeed.reddit('Music')],
        now: () => DateTime.utc(2026, 3, 1),
      );
      final List<NewsArticle> tech = await service.getArticles(
        categories: const <NewsCategory>[NewsCategory.techAi],
      );
      expect(tech, hasLength(1));
      expect(tech.single.categories.single, NewsCategory.techAi);
    });
  });
}

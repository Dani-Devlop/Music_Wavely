import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/news_dao.dart';
import 'package:wavely/data/remote/metadata_http.dart';
import 'package:wavely/features/news/data/news_article.dart';
import 'package:wavely/features/news/data/news_category.dart';
import 'package:wavely/features/news/data/news_prefs.dart';

/// Feed definition: a reddit JSON listing or an RSS/Atom document.
class NewsFeed {
  const NewsFeed._({
    required this.source,
    required this.url,
    required this.kind,
  });

  /// Reddit JSON listing under r/[sub].
  factory NewsFeed.reddit(String sub) => NewsFeed._(
        source: 'reddit/$sub',
        url: Uri.https(
          'www.reddit.com',
          '/r/$sub/new.json',
          <String, String>{'limit': '50'},
        ),
        kind: _FeedKind.redditJson,
      );

  /// Arbitrary RSS/Atom feed (built-in outlets and user custom feeds).
  factory NewsFeed.rss(String source, Uri url) =>
      NewsFeed._(source: source, url: url, kind: _FeedKind.rss);

  /// Built-in no-key feeds (live-verified shapes; see STAGE_2_2_REPORT).
  static final List<NewsFeed> builtIn = <NewsFeed>[
    NewsFeed.reddit('Music'),
    NewsFeed.reddit('hiphopheads'),
    NewsFeed.reddit('indieheads'),
    NewsFeed.rss('pitchfork', Uri.https('pitchfork.com', '/rss/news/')),
    NewsFeed.rss('nme', Uri.https('www.nme.com', '/news/feed')),
  ];

  /// Source label persisted with every article of this feed.
  final String source;

  final Uri url;
  final _FeedKind kind;
}

enum _FeedKind { redditJson, rss }

/// Music-news aggregator over no-key sources (Stage 2.2).
///
/// - Every host is rate-limited to 1 request/second via the shared
///   [RateLimiter] turnstile.
/// - Responses ride the existing [CachingHttpClient] (`http_cache` table,
///   30-minute TTL, stale-while-error offline behaviour). Pull-to-refresh
///   intentionally HONORS the cache — the offline-first convention used by
///   the discovery screen.
/// - Articles are classified on arrival, deduped by `(source, sourceId)`
///   and persisted through [NewsDao] for offline reads.
/// - [getArticles] NEVER throws: any feed failure degrades to the cached
///   database rows.
class NewsService {
  /// Creates the service.
  ///
  /// [feeds] replaces the built-in feed list (tests inject the fixture
  /// URLs). [now] injects the clock (rate limiter + tests).
  NewsService({
    required NewsDao dao,
    required NewsPrefs prefs,
    required CachingHttpClient http,
    List<NewsFeed>? feeds,
    DateTime Function()? now,
  })  : _dao = dao,
        _prefs = prefs,
        _http = http,
        _feeds = feeds ?? NewsFeed.builtIn,
        _now = now ?? DateTime.now;

  /// Client-side freshness window mirrored into the HTTP cache.
  static const Duration cacheTtl = Duration(minutes: 30);

  final NewsDao _dao;
  final NewsPrefs _prefs;
  final CachingHttpClient _http;
  final List<NewsFeed> _feeds;
  final DateTime Function() _now;

  final Map<String, RateLimiter> _limiters = <String, RateLimiter>{};

  RateLimiter _limiterFor(String host) => _limiters.putIfAbsent(
        host,
        () => RateLimiter(const Duration(seconds: 1), now: _now),
      );

  /// Fetches, merges and returns up to [limit] articles from the selected
  /// [categories] (empty selection = every category). Muted sources are
  /// filtered out. Never throws.
  Future<List<NewsArticle>> getArticles({
    required List<NewsCategory> categories,
    int limit = 30,
  }) async {
    final List<NewsArticle> fetched = await _fetchAndPersist();
    final List<NewsArticle> stored = await _storedArticles();
    final List<NewsArticle> visible = _mergeAndFilter(
      fetched: fetched,
      stored: stored,
      categories: categories,
    );
    return visible.take(limit).toList(growable: false);
  }

  /// Pull-to-refresh entry point. Per the offline-first convention the
  /// 30-minute HTTP cache is intentionally honored; the re-run only
  /// refreshes the merged view (mirrors the discovery screen contract).
  Future<List<NewsArticle>> refresh({
    required List<NewsCategory> categories,
    int limit = 30,
  }) => getArticles(categories: categories, limit: limit);

  // -- internals -------------------------------------------------------------

  List<NewsArticle> _mergeAndFilter({
    required List<NewsArticle> fetched,
    required List<NewsArticle> stored,
    required List<NewsCategory> categories,
  }) {
    final Map<String, NewsArticle> merged = <String, NewsArticle>{
      for (final NewsArticle article in stored) article.dedupeKey: article,
      for (final NewsArticle article in fetched) article.dedupeKey: article,
    };
    final Set<String> muted = _prefs.mutedSources.toSet();
    return merged.values
        .where((NewsArticle article) => !muted.contains(article.source))
        .where(
          (NewsArticle article) =>
              categories.isEmpty ||
              article.categories.any(categories.contains),
        )
        .toList()
      ..sort(
        (NewsArticle a, NewsArticle b) =>
            b.publishedAt.compareTo(a.publishedAt),
      );
  }

  Future<List<NewsArticle>> _fetchAndPersist() async {
    final List<NewsArticle> collected = <NewsArticle>[];
    final DateTime fetchedAt = _now();
    for (final NewsFeed feed in _feeds) {
      try {
        await _limiterFor(feed.url.host).waitTurn();
        final String body = await switch (await _http.getJson(feed.url, ttl: cacheTtl)) {
          Success<String>(:final value) => value,
          Err<String>() => throw StateError('feed failed: ${feed.source}'),
        };
        final List<NewsArticle> parsed = switch (feed.kind) {
          _FeedKind.redditJson => parseReddit(feed.source, body, fetchedAt),
          _FeedKind.rss => parseRss(feed.source, body, fetchedAt),
        };
        collected.addAll(parsed);
      } on Object {
        // One failed feed must not sink the rest; offline rows cover it.
        continue;
      }
    }
    if (collected.isNotEmpty) {
      try {
        await _dao.upsertAll(
          collected.map((NewsArticle a) => a.toCompanion()).toList(),
        );
      } on Object {
        // Storage failure: keep serving from memory.
      }
    }
    return collected;
  }

  Future<List<NewsArticle>> _storedArticles() async {
    try {
      final List<NewsArticleRow> rows = await _dao.allStored();
      return rows.map(NewsArticle.fromRow).toList(growable: false);
    } on Object {
      return const <NewsArticle>[];
    }
  }

  /// Reddit listing JSON: `data.children[].data` objects. Public so the
  /// fixture tests exercise the exact production parser.
  static List<NewsArticle> parseReddit(
    String source,
    String body,
    DateTime fetchedAt,
  ) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) {
        return const <NewsArticle>[];
      }
      final Object? data = decoded['data'];
      final Object? children =
          data is Map<String, Object?> ? data['children'] : null;
      if (children is! List) {
        return const <NewsArticle>[];
      }
      final List<NewsArticle> articles = <NewsArticle>[];
      for (final Object? child in children) {
        if (child is! Map<String, Object?>) {
          continue;
        }
        final Object? d = child['data'];
        if (d is! Map<String, Object?>) {
          continue;
        }
        final String id = (d['id'] ?? '').toString();
        final String title = (d['title'] ?? '').toString().trim();
        if (id.isEmpty || title.isEmpty) {
          continue;
        }
        final String selftext = (d['selftext'] ?? '').toString().trim();
        final String permalink = (d['permalink'] ?? '').toString();
        final String externalUrl = (d['url'] ?? '').toString();
        final String url = externalUrl.startsWith('http')
            ? externalUrl
            : 'https://www.reddit.com$permalink';
        final String thumbnail = (d['thumbnail'] ?? '').toString();
        final Object? createdUtc = d['created_utc'];
        final DateTime publishedAt = createdUtc is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (createdUtc * 1000).round(),
                isUtc: true,
              )
            : fetchedAt;
        articles.add(
          NewsArticle(
            source: source,
            sourceId: id,
            title: title,
            summary: selftext.isEmpty
                ? 'Discussion thread on '
                    'r/${(d['subreddit'] ?? source).toString()}'
                : selftext,
            url: url,
            imageUrl: thumbnail.startsWith('http') ? thumbnail : null,
            publishedAt: publishedAt,
            fetchedAt: fetchedAt,
            categories: <NewsCategory>[
              NewsCategoryClassifier.classify(title, selftext),
            ],
          ),
        );
      }
      return articles;
    } on Object {
      return const <NewsArticle>[];
    }
  }

  /// RSS 2.0 / Atom-ish parse via the `html` package (a dependency since
  /// Stage 2.1). Handles `<item>` (RSS) and `<entry>` (Atom). Public so
  /// the fixture tests exercise the exact production parser.
  static List<NewsArticle> parseRss(
    String source,
    String body,
    DateTime fetchedAt,
  ) {
    try {
      final dom.Document document = html_parser.parse(body);
      final List<dom.Element> items = <dom.Element>[
        ...document.querySelectorAll('item'),
        ...document.querySelectorAll('entry'),
      ];
      final List<NewsArticle> articles = <NewsArticle>[];
      for (final dom.Element item in items) {
        final String title = _textOf(item, 'title');
        final String link = _textOf(item, 'link').isNotEmpty
            ? _textOf(item, 'link')
            : (_attrOf(item.querySelector('link'), 'href') ?? '');
        if (title.isEmpty || link.isEmpty) {
          continue;
        }
        final String guid =
            _textOf(item, 'guid').isNotEmpty ? _textOf(item, 'guid') : link;
        final String rawDescription = _textOf(item, 'description').isNotEmpty
            ? _textOf(item, 'description')
            : _textOf(item, 'summary');
        final String summary = _stripTags(rawDescription);
        final String dateText = _textOf(item, 'pubDate').isNotEmpty
            ? _textOf(item, 'pubDate')
            : _textOf(item, 'published');
        final DateTime publishedAt = _parseDate(dateText) ?? fetchedAt;
        String? imageUrl = _attrOf(item.querySelector('thumbnail'), 'url');
        imageUrl ??= _enclosureImage(item);
        articles.add(
          NewsArticle(
            source: source,
            sourceId: guid,
            title: title,
            summary: summary.isEmpty ? title : summary,
            url: link,
            imageUrl: (imageUrl != null && imageUrl.startsWith('http'))
                ? imageUrl
                : null,
            publishedAt: publishedAt,
            fetchedAt: fetchedAt,
            categories: <NewsCategory>[
              NewsCategoryClassifier.classify(title, summary),
            ],
          ),
        );
      }
      return articles;
    } on Object {
      return const <NewsArticle>[];
    }
  }

  static String _textOf(dom.Element parent, String tag) =>
      parent.getElementsByTagName(tag).isNotEmpty
          ? parent.getElementsByTagName(tag).first.text.trim()
          : '';

  static String? _attrOf(dom.Element? element, String name) =>
      element?.attributes[name];

  static String? _enclosureImage(dom.Element item) {
    for (final dom.Element enclosure
        in item.getElementsByTagName('enclosure')) {
      final String type = (enclosure.attributes['type'] ?? '').toLowerCase();
      final String url = enclosure.attributes['url'] ?? '';
      if (url.isNotEmpty &&
          (type.startsWith('image') || url.contains('/image'))) {
        return url;
      }
    }
    return null;
  }

  static String _stripTags(String html) =>
      html_parser.parse(html).documentElement?.text.trim() ?? html.trim();

  /// RFC-822 (`Mon, 02 Jan 2006 15:04:05 GMT`) and ISO8601 dates; unknown
  /// formats degrade to `null`.
  static DateTime? _parseDate(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) {
      return null;
    }
    final DateTime? iso = DateTime.tryParse(text);
    if (iso != null) {
      return iso;
    }
    final RegExp rfc822 = RegExp(
      r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{2,4})\s+(\d{2}):(\d{2})(?::(\d{2}))?',
    );
    final RegExpMatch? match = rfc822.firstMatch(text);
    if (match == null) {
      return null;
    }
    const List<String> months = <String>[
      'jan', 'feb', 'mar', 'apr', 'may', 'jun',
      'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
    ];
    final int month = months.indexOf(match.group(2)!.toLowerCase()) + 1;
    if (month <= 0) {
      return null;
    }
    final int day = int.parse(match.group(1)!);
    final String yearRaw = match.group(3)!;
    final int year =
        yearRaw.length == 2 ? 2000 + int.parse(yearRaw) : int.parse(yearRaw);
    return DateTime.utc(
      year,
      month,
      day,
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      match.group(6) == null ? 0 : int.parse(match.group(6)!),
    );
  }
}

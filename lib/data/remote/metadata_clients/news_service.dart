import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/remote/metadata_clients/rss_client.dart';

/// One aggregated music-news headline (metadata only).
class NewsItem {
  /// Creates a headline.
  const NewsItem({
    required this.source,
    required this.title,
    required this.url,
    this.publishedAt,
  });

  /// Feed label, e.g. `Pitchfork` / `NME`.
  final String source;

  /// Headline text (parsed by [RssClient], entities decoded).
  final String title;

  /// Absolute article URL.
  final String url;

  /// Publication date when the feed supplied a parseable one.
  final DateTime? publishedAt;
}

/// Aggregates the music-news RSS/Atom feeds into one newest-first list.
///
/// Sources (docs/METADATA_SOURCES.md, live-verified): Pitchfork
/// (`/feed/feed-news/rss`, 301 → followed by http.Client) and NME
/// (`/rss/news`). Each feed is fetched independently through [RssClient]
/// (1 h TTL per feed); when ONE feed fails the other still contributes —
/// the call fails only when BOTH fail. Results are memoized for 5 minutes
/// between refetches; [headlines] `forceRefresh: true` bypasses the memo
/// (pull-to-refresh) but still honors the underlying HTTP cache. Never
/// throws.
class NewsService {
  /// Creates the service; [now] is injectable for tests.
  NewsService({required RssClient rss, DateTime Function()? now})
      : _rss = rss,
        _now = now ?? DateTime.now;

  /// Minimum in-memory age before a network refetch is allowed.
  static const Duration minRefetchInterval = Duration(minutes: 5);

  /// Aggregated feed sources (label + URL).
  static final List<(String, Uri)> feeds = <(String, Uri)>[
    ('Pitchfork', Uri.parse('https://pitchfork.com/feed/feed-news/rss')),
    ('NME', Uri.parse('https://www.nme.com/rss/news')),
  ];

  final RssClient _rss;
  final DateTime Function() _now;
  DateTime? _lastFetchAt;
  List<NewsItem>? _memo;

  /// Aggregated headlines, newest first (undated items last).
  Future<Result<List<NewsItem>>> headlines({bool forceRefresh = false}) async {
    final memo = _memo;
    final last = _lastFetchAt;
    if (!forceRefresh &&
        memo != null &&
        last != null &&
        _now().difference(last) < minRefetchInterval) {
      return Result<List<NewsItem>>.success(memo);
    }
    final results = await Future.wait<Result<List<NewsItem>>>(
      <Future<Result<List<NewsItem>>>>[
        for (final (source, url) in feeds) _fetchOne(source, url),
      ],
    );
    final merged = <NewsItem>[];
    Failure? failure;
    for (final result in results) {
      if (result case Err<List<NewsItem>>(failure: final f)) {
        failure ??= f;
        continue;
      }
      if (result case Success<List<NewsItem>>(:final value)) {
        merged.addAll(value);
      }
    }
    if (merged.isEmpty && failure != null) {
      return Result<List<NewsItem>>.err(failure);
    }
    merged.sort(_compare);
    _memo = List<NewsItem>.unmodifiable(merged);
    _lastFetchAt = _now();
    return Result<List<NewsItem>>.success(_memo!);
  }

  Future<Result<List<NewsItem>>> _fetchOne(String source, Uri url) async {
    final result = await _rss.fetch(url);
    return result.map(
      (items) => <NewsItem>[
        for (final item in items)
          NewsItem(
            source: source,
            title: item.title,
            url: item.link,
            publishedAt: item.publishedAt,
          ),
      ],
    );
  }

  static int _compare(NewsItem a, NewsItem b) {
    final aDate = a.publishedAt;
    final bDate = b.publishedAt;
    if (aDate == null && bDate == null) {
      return 0;
    }
    if (aDate == null) {
      return 1;
    }
    if (bDate == null) {
      return -1;
    }
    return bDate.compareTo(aDate);
  }
}

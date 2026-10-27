import 'dart:convert';

import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/remote/metadata_http.dart';

/// One parsed feed entry (RSS 2.0 `<item>` or Atom `<entry>`).
class RssItem {
  /// Creates a feed entry.
  const RssItem({required this.title, required this.link, this.publishedAt});

  /// Entry title (tags stripped, entities decoded, whitespace collapsed).
  final String title;

  /// Entry link (Atom `href` attribute or RSS `<link>` text).
  final String link;

  /// `pubDate` (RSS) / `updated`+`published` (Atom) when parseable.
  ///
  /// NOTE: RFC-822 dates are parsed timezone-naive (local clock), so
  /// cross-feed ordering has at most a timezone-offset skew; ISO/Atom
  /// dates keep their real instant.
  final DateTime? publishedAt;
}

/// Tiny regex-based RSS 2.0 + Atom fetcher/parser over [CachingHttpClient].
///
/// LIMITATIONS (deliberate — no XML dependency):
/// - CDATA sections are unwrapped to their raw text (no re-encoding).
/// - Only these entities are decoded: `&amp;` `&lt;` `&gt;` `&quot;`
///   `&#39;` (and `&apos;`); numeric entities stay literal.
/// - Inline markup inside title/link is stripped, not interpreted.
/// - Namespaced extension elements and `content:encoded` are ignored.
/// - A feed-shaped response with zero entries parses to an empty list
///   (the HTTP layer already guarantees a 200).
///
/// 301/302 redirects are followed by the underlying `http.Client`
/// (Pitchfork's feed redirects to its final URL). Default cache TTL 1 h.
/// Never throws.
class RssClient {
  /// Creates the client.
  RssClient({required CachingHttpClient http}) : _http = http;

  /// Default feed cache lifetime (docs/METADATA_SOURCES.md: 1 h).
  static const Duration defaultTtl = Duration(hours: 1);

  final CachingHttpClient _http;

  /// Fetches and parses the feed at [url] into headline items.
  Future<Result<List<RssItem>>> fetch(
    Uri url, {
    Duration ttl = defaultTtl,
  }) async {
    final response = await _http.getJson(url, ttl: ttl);
    return response.fold(
      onErr: (failure) => Result<List<RssItem>>.err(failure),
      onSuccess: parse,
    );
  }

  /// Parses a raw RSS/Atom [body]; exposed for reuse and testing.
  static Result<List<RssItem>> parse(String body) {
    final unwrapped = _stripCdata(body);
    final blocks = <String>[
      for (final match in _rssItemRegex.allMatches(unwrapped))
        match.group(1) ?? '',
      for (final match in _atomEntryRegex.allMatches(unwrapped))
        match.group(1) ?? '',
    ];
    final items = <RssItem>[
      for (final block in blocks)
        if (_parseBlock(block) case final item?) item,
    ];
    return Result<List<RssItem>>.success(items);
  }

  static final RegExp _rssItemRegex =
      RegExp(r'<item\b[^>]*>([\s\S]*?)</item>', caseSensitive: false);
  static final RegExp _atomEntryRegex =
      RegExp(r'<entry\b[^>]*>([\s\S]*?)</entry>', caseSensitive: false);
  static final RegExp _tagRegex = RegExp(r'<[^>]+>');
  static final RegExp _cdataRegex =
      RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>');

  static const Map<String, int> _months = <String, int>{
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  static RssItem? _parseBlock(String block) {
    final title = _clean(_firstTag(block, 'title'));
    if (title.isEmpty) {
      return null;
    }
    final link = _link(block);
    if (link == null || link.isEmpty) {
      return null;
    }
    final published = _date(_firstTag(block, 'pubDate')) ??
        _date(_firstTag(block, 'updated')) ??
        _date(_firstTag(block, 'published'));
    return RssItem(title: title, link: link, publishedAt: published);
  }

  static String? _firstTag(String block, String tag) {
    final match = RegExp(
      '<$tag\\b[^>]*>([\\s\\S]*?)</$tag>',
      caseSensitive: false,
    ).firstMatch(block);
    return match?.group(1);
  }

  static String? _link(String block) {
    // Atom first: <link rel="alternate" type="text/html" href="..."/>.
    final href = RegExp(
      r'<link\b[^>]*\bhref=["'']([^"'']+)["'']',
      caseSensitive: false,
    ).firstMatch(block)?.group(1);
    if (href != null && href.trim().isNotEmpty) {
      return _clean(href);
    }
    // RSS 2.0: <link>https://...</link>.
    final rss = RegExp(
      r'<link\b[^>]*>([\s\S]*?)</link>',
      caseSensitive: false,
    ).firstMatch(block)?.group(1);
    return rss == null ? null : _clean(rss);
  }

  static String _clean(String raw) => _decodeEntities(
        raw.replaceAll(_tagRegex, ' ').replaceAll(_cdataRegex, '').trim(),
      ).replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _stripCdata(String body) =>
      body.replaceAllMapped(_cdataRegex, (match) => match.group(1) ?? '');

  static String _decodeEntities(String raw) => raw
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  static DateTime? _date(String? raw) {
    if (raw == null) {
      return null;
    }
    final text = _clean(raw);
    if (text.isEmpty) {
      return null;
    }
    final iso = DateTime.tryParse(text);
    if (iso != null) {
      return iso;
    }
    // RFC-822 (RSS 2.0): `Mon, 27 Oct 2026 10:00:00 GMT` — parsed
    // timezone-naive (local) since dart:io's HttpDate is off-limits.
    final match = RegExp(
      r'(\d{1,2})\s+([A-Za-z]{3,})\s+(\d{4})'
      r'(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?',
    ).firstMatch(text);
    if (match == null) {
      return null;
    }
    final month = _months[match.group(2)!.substring(0, 3).toLowerCase()];
    if (month == null) {
      return null;
    }
    return DateTime(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4) ?? '0'),
      int.parse(match.group(5) ?? '0'),
      int.parse(match.group(6) ?? '0'),
    );
  }
}

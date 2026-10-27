import 'dart:convert';

import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/remote/metadata_http.dart';

/// One archive.org catalog item (free-catalog discovery, metadata only).
class ArchiveItem {
  /// Creates a catalog item.
  const ArchiveItem({required this.identifier, this.title});

  /// archive.org identifier (drives the public details page URL).
  final String identifier;

  /// Item title; archive.org returns a list for multi-titled items —
  /// the first non-empty entry wins, `null` when absent.
  final String? title;
}

/// archive.org advancedsearch client (metadata only).
///
/// Endpoint (docs/METADATA_SOURCES.md, live-verified):
/// `GET /advancedsearch.php?q=<q>&fl[]=identifier&fl[]=title&rows=N`
/// `&page=1&output=json` — the duplicate `fl[]` key cannot be expressed
/// through `Uri.replace(queryParameters:)`, so the query string is built
/// manually. 24 h cache TTL; every call returns a [Result], never throws.
class ArchiveOrgClient {
  /// Creates the client.
  ArchiveOrgClient({required CachingHttpClient http}) : _http = http;

  static const Duration _ttl = Duration(hours: 24);

  final CachingHttpClient _http;

  /// Searches the catalog for [query] (up to [rows] results); an empty
  /// docs list resolves to an empty success.
  Future<Result<List<ArchiveItem>>> search(String query, {int rows = 20}) async {
    final url = Uri.parse(
      'https://archive.org/advancedsearch.php'
      '?q=${Uri.encodeQueryComponent(query)}'
      '&fl[]=identifier&fl[]=title'
      '&rows=$rows&page=1&output=json',
    );
    final response = await _http.getJson(url, ttl: _ttl);
    return response.fold(
      onErr: (failure) => Result<List<ArchiveItem>>.err(failure),
      onSuccess: _parseSearch,
    );
  }

  Result<List<ArchiveItem>> _parseSearch(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return const Result<List<ArchiveItem>>.err(
          Failure.parsing(message: 'Unexpected archive.org payload'),
        );
      }
      final responseNode = decoded['response'];
      final docs =
          responseNode is Map<String, dynamic> ? responseNode['docs'] : null;
      if (docs is! List) {
        return const Result<List<ArchiveItem>>.success([]);
      }
      final items = <ArchiveItem>[
        for (final doc in docs)
          if (doc is Map<String, dynamic>)
            if (_toItem(doc) case final item?) item,
      ];
      return Result<List<ArchiveItem>>.success(items);
    } on FormatException catch (error) {
      return Result<List<ArchiveItem>>.err(
        Failure.parsing(
          message: 'Malformed archive.org response',
          cause: error,
        ),
      );
    }
  }

  static ArchiveItem? _toItem(Map<String, dynamic> doc) {
    final identifier = doc['identifier'];
    if (identifier is! String || identifier.isEmpty) {
      return null;
    }
    return ArchiveItem(identifier: identifier, title: _firstText(doc['title']));
  }

  static String? _firstText(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    if (value is List) {
      for (final entry in value) {
        if (entry is String && entry.isNotEmpty) {
          return entry;
        }
      }
    }
    return null;
  }
}

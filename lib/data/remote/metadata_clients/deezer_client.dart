import 'dart:convert';

import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/remote/metadata_http.dart';

/// One Deezer artist (search / related-artists row).
///
/// Plain immutable class (no codegen); no equality contract is
/// documented — compare fields explicitly where needed.
class DeezerArtist {
  /// Creates a Deezer artist.
  const DeezerArtist({
    required this.id,
    required this.name,
    this.pictureUrl,
  });

  /// Numeric Deezer artist id (drives `/artist/<id>/related`).
  final int id;

  /// Artist display name.
  final String name;

  /// `picture_medium` URL when present.
  final String? pictureUrl;
}

/// One Deezer album (`GET /album/<id>` response subset).
class DeezerAlbum {
  /// Creates a Deezer album.
  const DeezerAlbum({
    required this.id,
    required this.title,
    this.coverUrl,
    this.releaseDate,
  });

  /// Numeric Deezer album id.
  final int id;

  /// Album title.
  final String title;

  /// `cover_medium` URL when present.
  final String? coverUrl;

  /// `release_date` (`yyyy-MM-dd`) when present.
  final String? releaseDate;
}

/// Deezer public API client (metadata only — no playback, no downloads).
///
/// Endpoints (docs/METADATA_SOURCES.md, live-verified):
/// - `GET /search/artist?q=<q>&limit=1`
/// - `GET /artist/<id>/related?limit=N` — returned `Access-Denied` from
///   one sandbox IP during verification; ANY failure here is surfaced as
///   [Result.err] and the UI hides the section (graceful degradation).
/// - `GET /album/<id>`
///
/// Deezer signals API errors with HTTP 200 + an `error` envelope; that
/// envelope is detected and mapped to [Failure.network]. 5 req/s via the
/// default limiter, 6 h cache TTL. Never throws.
class DeezerClient {
  /// Creates the client; [rateLimiter] defaults to 5 req/s (Deezer docs).
  DeezerClient({required CachingHttpClient http, RateLimiter? rateLimiter})
      : _http = http,
        _rateLimiter =
            rateLimiter ?? RateLimiter(const Duration(milliseconds: 200));

  static const Duration _ttl = Duration(hours: 6);

  final CachingHttpClient _http;
  final RateLimiter _rateLimiter;

  /// Searches one artist by [q]; resolves to `null` on an empty result.
  Future<Result<DeezerArtist?>> searchArtist(String q) async {
    await _rateLimiter.waitTurn();
    final url = Uri.parse('https://api.deezer.com/search/artist')
        .replace(queryParameters: <String, String>{'q': q, 'limit': '1'});
    final response = await _http.getJson(url, ttl: _ttl);
    return response.fold(
      onErr: (failure) => Result<DeezerArtist?>.err(failure),
      onSuccess: _parseArtistPayload,
    );
  }

  /// Artists related to Deezer artist [id] (up to [limit]).
  Future<Result<List<DeezerArtist>>> relatedArtists(
    int id, {
    int limit = 10,
  }) async {
    await _rateLimiter.waitTurn();
    final url = Uri.parse('https://api.deezer.com/artist/$id/related')
        .replace(queryParameters: <String, String>{'limit': '$limit'});
    final response = await _http.getJson(url, ttl: _ttl);
    return response.fold(
      onErr: (failure) => Result<List<DeezerArtist>>.err(failure),
      onSuccess: _parseRelatedPayload,
    );
  }

  /// Loads album metadata for [id]; `null` on an unknown/empty album.
  Future<Result<DeezerAlbum?>> album(int id) async {
    await _rateLimiter.waitTurn();
    final url = Uri.parse('https://api.deezer.com/album/$id');
    final response = await _http.getJson(url, ttl: _ttl);
    return response.fold(
      onErr: (failure) => Result<DeezerAlbum?>.err(failure),
      onSuccess: _parseAlbumPayload,
    );
  }

  Result<DeezerArtist?> _parseArtistPayload(String body) {
    final decoded = _decode(body);
    final Object? data;
    switch (decoded) {
      case Err<Object?>(:final failure):
        return Result<DeezerArtist?>.err(failure);
      case final Success<Object?> success:
        data = success.value;
    }
    final list = data is Map<String, dynamic> ? data['data'] : null;
    final first = list is List && list.isNotEmpty ? list.first : null;
    if (first is! Map<String, dynamic>) {
      return const Result<DeezerArtist?>.success(null);
    }
    final id = first['id'];
    final name = first['name'];
    if (id is! num || name is! String) {
      return const Result<DeezerArtist?>.success(null);
    }
    final picture = first['picture_medium'];
    return Result<DeezerArtist?>.success(
      DeezerArtist(
        id: id.round(),
        name: name,
        pictureUrl: picture is String ? picture : null,
      ),
    );
  }

  Result<List<DeezerArtist>> _parseRelatedPayload(String body) {
    final decoded = _decode(body);
    final Object? data;
    switch (decoded) {
      case Err<Object?>(:final failure):
        return Result<List<DeezerArtist>>.err(failure);
      case final Success<Object?> success:
        data = success.value;
    }
    final list = data is Map<String, dynamic> ? data['data'] : null;
    if (list is! List) {
      return const Result<List<DeezerArtist>>.success([]);
    }
    final parsed = <DeezerArtist>[
      for (final entry in list)
        if (entry is Map<String, dynamic>)
          if (_toArtist(entry) case final artist?) artist,
    ];
    return Result<List<DeezerArtist>>.success(parsed);
  }

  Result<DeezerAlbum?> _parseAlbumPayload(String body) {
    final decoded = _decode(body);
    final Object? data;
    switch (decoded) {
      case Err<Object?>(:final failure):
        return Result<DeezerAlbum?>.err(failure);
      case final Success<Object?> success:
        data = success.value;
    }
    if (data is! Map<String, dynamic>) {
      return const Result<DeezerAlbum?>.success(null);
    }
    final id = data['id'];
    final title = data['title'];
    if (id is! num || title is! String) {
      return const Result<DeezerAlbum?>.success(null);
    }
    final cover = data['cover_medium'];
    final releaseDate = data['release_date'];
    return Result<DeezerAlbum?>.success(
      DeezerAlbum(
        id: id.round(),
        title: title,
        coverUrl: cover is String ? cover : null,
        releaseDate: releaseDate is String ? releaseDate : null,
      ),
    );
  }

  /// jsonDecode + Deezer's HTTP-200 `error` envelope detection.
  Result<Object?> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> &&
          decoded['error'] is Map<String, dynamic>) {
        final error = decoded['error'] as Map<String, dynamic>;
        final message = error['message'];
        return Result<Object?>.err(
          Failure.network(
            message: 'Deezer API error: '
                '${message is String ? message : 'unknown'}',
          ),
        );
      }
      return Result<Object?>.success(decoded);
    } on FormatException catch (error) {
      return Result<Object?>.err(
        Failure.parsing(message: 'Malformed Deezer response', cause: error),
      );
    }
  }

  static DeezerArtist? _toArtist(Map<String, dynamic> entry) {
    final id = entry['id'];
    final name = entry['name'];
    if (id is! num || name is! String) {
      return null;
    }
    final picture = entry['picture_medium'];
    return DeezerArtist(
      id: id.round(),
      name: name,
      pictureUrl: picture is String ? picture : null,
    );
  }
}

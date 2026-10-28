import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/http_cache_dao.dart';

/// Shared HTTP plumbing for the Stage 1.2 metadata clients.
abstract final class MetadataHttp {
  /// Stage 3 audit (SEC-5): per-request timeout — a stalled server must not
  /// hang the shared rate-limiter queue indefinitely.
  static const Duration kMetadataHttpTimeout = Duration(seconds: 15);

  /// Canonical User-Agent sent with every metadata request.
  ///
  /// MusicBrainz requires a descriptive UA (their etiquette policy);
  /// every other source receives the same header for politeness and
  /// traceability.
  static const String userAgent =
      'Wavely/1.0 (https://github.com/Dani-Devlop/Music_Wavely)';
}

/// Simple serial rate limiter (one instance per remote host/client).
///
/// Not a token bucket — a turnstile: each [waitTurn] completes at least
/// [minInterval] after the previous turn STARTED, and concurrent callers
/// queue up behind each other in call order, so bursts stay ordered and
/// capped at one request per [minInterval] (MB 1/s, Deezer 5/s, ...).
///
/// Pure Dart (`dart:async` only). Tests inject [now] to control the
/// clock the interval math runs against.
class RateLimiter {
  /// Creates a limiter enforcing [minInterval] between turns.
  RateLimiter(this.minInterval, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// Minimum spacing between two consecutive [waitTurn] completions.
  final Duration minInterval;

  final DateTime Function() _now;

  DateTime? _lastTurnAt;
  Future<void> _queue = Future<void>.value();

  /// Waits until this instance's next turn is due. Never throws.
  Future<void> waitTurn() {
    final completer = Completer<void>();
    _queue = _queue.then((_) => _acquire(completer));
    return completer.future;
  }

  Future<void> _acquire(Completer<void> completer) async {
    final last = _lastTurnAt;
    final now = _now();
    final remaining =
        last == null ? Duration.zero : minInterval - now.difference(last);
    if (remaining <= Duration.zero) {
      _lastTurnAt = now;
      completer.complete();
      return;
    }
    Timer(remaining, () {
      _lastTurnAt = _now();
      completer.complete();
    });
  }
}

/// HTTP GET client with a persistent [HttpCacheDao] backing store.
///
/// Read-through/write-through on success, offline-first on failure:
///
/// - A cache row that has not expired (per the injectable [now] clock)
///   is returned without touching the network.
/// - A 200 response is stored under the deterministic request key with
///   `expiresAt = now + ttl` and returned as success.
/// - Any other status resolves to `Failure.network` (no cache fallback:
///   the server answered, so the body would be an error document).
/// - If the request THROWS (device offline, DNS failure, TLS error),
///   the cached body is returned EVEN IF ITS TTL HAS EXPIRED —
///   "stale-while-error": for read-only metadata a stale answer beats an
///   error screen. With no cached row at all the call resolves to
///   `Failure.network`.
///
/// [getJson] never throws; every path returns a [Result].
///
/// Expiry is checked against the injected clock (constructor [now]),
/// NOT against `HttpCacheDao.get` (whose freshness check pins
/// `DateTime.now()`); rows are therefore read straight from the
/// `http_cache` table through the DAO's public drift surface
/// ([DatabaseAccessor.select] + the generated table getter) so tests
/// can fast-forward time deterministically.
class CachingHttpClient {
  /// Creates the client.
  ///
  /// [cacheDao] is the shared persistent cache. [client] defaults to a
  /// plain `http.Client()` (web-safe). [ttlFor] optionally overrides the
  /// per-call [CachingHttpClient.getJson] `ttl` per URL (single policy
  /// table for all clients). [now] defaults to [DateTime.now] and is
  /// the ONLY clock used for freshness decisions in this class.
  CachingHttpClient({
    required HttpCacheDao cacheDao,
    http.Client? client,
    Duration? Function(Uri url)? ttlFor,
    DateTime Function()? now,
  })  : _cacheDao = cacheDao,
        _client = client ?? http.Client(),
        _ttlFor = ttlFor,
        _now = now ?? DateTime.now;

  final HttpCacheDao _cacheDao;
  final http.Client _client;
  final Duration? Function(Uri url)? _ttlFor;
  final DateTime Function() _now;

  /// GETs [url] as text (JSON bodies stay strings; parsing is the
  /// client's job) with read-through caching. Never throws.
  Future<Result<String>> getJson(
    Uri url, {
    required Duration ttl,
    Map<String, String>? extraHeaders,
  }) async {
    final effectiveTtl = _ttlFor?.call(url) ?? ttl;
    final requestKey = HttpCacheDao.requestKey('GET', url.toString());
    try {
      final cached = await _readRow(requestKey);
      if (cached != null && !cached.expiresAt.isBefore(_now())) {
        return Result<String>.success(cached.body);
      }
      // Stage 3 audit (SEC-5): bound the request so a stalled server cannot
      // hang the rate-limiter queue indefinitely.
      final response = await _client
          .get(
            url,
            headers: <String, String>{
              'user-agent': MetadataHttp.userAgent,
              ...?extraHeaders,
            },
          )
          .timeout(kMetadataHttpTimeout);
      if (response.statusCode != 200) {
        return Result<String>.err(
          Failure.network(
            message: 'HTTP ${response.statusCode} from ${url.host}',
          ),
        );
      }
      // JSON is UTF-8 by spec (RFC 8259) even when the server omits the
      // charset header (the `http` package would otherwise fall back to
      // latin1); malformed bytes are replaced, never thrown.
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      try {
        await _cacheDao.put(
          requestKey: requestKey,
          body: body,
          statusCode: response.statusCode,
          expiresAt: _now().add(effectiveTtl),
        );
      } on Object catch (_) {
        // Storage failures must not mask a good response.
      }
      return Result<String>.success(body);
    } on Object catch (error) {
      // Stale-while-error: network threw (offline, DNS, TLS, ...) —
      // serve ANY cached row, expired or not.
      final stale = await _readRow(requestKey);
      if (stale != null) {
        return Result<String>.success(stale.body);
      }
      return Result<String>.err(
        Failure.network(message: 'Request failed: $error', cause: error),
      );
    }
  }

  Future<HttpCacheRow?> _readRow(String requestKey) async {
    try {
      final query = _cacheDao.select(_cacheDao.httpCache)
        ..where((row) => row.requestKey.equals(requestKey));
      return await query.getSingleOrNull();
    } on Object catch (_) {
      return null;
    }
  }
}

import 'package:dio/dio.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/lyrics_provider.dart';
import 'package:wavely/features/lyrics/data/lyrics_cache.dart';
import 'package:wavely/features/lyrics/domain/lrc_parser.dart';

/// LRCLIB (https://lrclib.net) lyrics provider.
///
/// Verified response shapes (live API):
/// - `GET /api/get?artist_name=&track_name=&album_name=&duration=` ->
///   `{id, trackName, artistName, albumName, duration, instrumental,
///   plainLyrics, syncedLyrics}` (fields null when absent).
/// - `GET /api/search?track_name=&artist_name=` -> JSON array of the same
///   record shape.
///
/// Contract: fetch NEVER throws — exact-match 404 falls back to
/// `/api/search`; every other failure (including the 5s timeout) resolves
/// to null so the provider chain can continue gracefully.
class LrclibLyricsProvider implements LyricsProvider {
  LrclibLyricsProvider({required Dio dio, required LyricsCache cache})
      : _dio = dio,
        _cache = cache;

  static const String providerId = 'lrclib';

  /// Base URL of the LRCLIB instance (named const instead of a magic
  /// string at call sites; the Dio instance is configured by the caller).
  static const String baseUrl = 'https://lrclib.net';

  /// Request timeout — a slow lyric lookup must never block playback.
  static const Duration _timeout = Duration(seconds: 5);

  static const String _getPath = '/api/get';
  static const String _searchPath = '/api/search';

  final Dio _dio;
  final LyricsCache _cache;

  @override
  String get id => providerId;

  @override
  Future<LyricsResult?> fetch(Track t) async {
    final trackId = t.id;
    if (trackId == null) {
      return null;
    }
    final record = await _resolveRecord(t);
    if (record == null) {
      return null;
    }
    final syncedRaw = record['syncedLyrics'];
    final plainRaw = record['plainLyrics'];
    final syncedText =
        syncedRaw is String && syncedRaw.trim().isNotEmpty ? syncedRaw : null;
    final plainText =
        plainRaw is String && plainRaw.trim().isNotEmpty ? plainRaw : null;
    if (syncedText == null && plainText == null) {
      return null;
    }
    try {
      await _cache.upsert(
        trackId: trackId,
        provider: providerId,
        syncedLrc: syncedText,
        plainText: plainText,
      );
    } on Object catch (_) {
      // Cache failures must not break lyric delivery.
    }
    return syncedText != null
        ? LrcParser.parse(syncedText)
        : LrcParser.parse(plainText!);
  }

  Future<Map<String, dynamic>?> _resolveRecord(Track t) async {
    final exactQuery = <String, dynamic>{
      'track_name': t.title,
      'artist_name': t.artistOrUnknown,
      if (t.album != null && t.album!.trim().isNotEmpty)
        'album_name': t.album,
      'duration': t.durationMs ~/ 1000,
    };
    Map<String, dynamic>? record;
    try {
      record = _asRecord(await _requestRaw(_getPath, exactQuery));
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) {
        return null; // network/server failure: no fallback per contract.
      }
    } on Object catch (_) {
      return null;
    }
    if (record != null && _hasLyrics(record)) {
      return record;
    }
    final searchQuery = <String, dynamic>{
      'track_name': t.title,
      'artist_name': t.artistOrUnknown,
    };
    try {
      final data = await _requestRaw(_searchPath, searchQuery);
      if (data is! List) {
        return record;
      }
      for (final entry in data) {
        if (entry is! Map) {
          continue;
        }
        final candidate = Map<String, dynamic>.from(entry);
        if (_hasLyrics(candidate)) {
          return candidate;
        }
      }
    } on Object catch (_) {
      return record;
    }
    return record;
  }

  bool _hasLyrics(Map<String, dynamic> record) {
    final synced = record['syncedLyrics'];
    final plain = record['plainLyrics'];
    return (synced is String && synced.trim().isNotEmpty) ||
        (plain is String && plain.trim().isNotEmpty);
  }

  Map<String, dynamic>? _asRecord(Object? data) =>
      data is Map<String, dynamic> ? data : null;

  Future<Object?> _requestRaw(
    String path,
    Map<String, dynamic> query,
  ) async {
    return _dio.get<dynamic>(
      path,
      queryParameters: query,
      options: Options(
        sendTimeout: _timeout,
        receiveTimeout: _timeout,
      ),
    ).then((response) => response.data);
  }
}

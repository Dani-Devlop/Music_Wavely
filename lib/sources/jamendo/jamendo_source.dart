import 'package:dio/dio.dart';

import 'package:wavely/data/remote/metadata_http.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/source_file.dart';
import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/sources/download_file_exports.dart';
import 'package:wavely/sources/source_exception.dart';

/// Parsed Jamendo track object (v3.0 API `results[]` entry).
///
/// Hand-rolled parsing; every field tolerant of missing keys.
class JamendoTrackResult {
  /// Creates a parsed result.
  const JamendoTrackResult({
    required this.id,
    required this.name,
    this.artistName = '',
    this.albumName = '',
    this.genre = '',
    this.durationSeconds = 0,
    this.audioUrl = '',
    this.audioDownloadUrl = '',
    this.licenseCcurl = '',
    this.image = '',
  });

  /// Parses a `results[]` entry.
  factory JamendoTrackResult.fromJson(Map<String, dynamic> json) {
    final Object? artist = json['artist'];
    final Object? album = json['album'];
    return JamendoTrackResult(
      id: (json['id']?.toString()) ?? '',
      name: (json['name'] as String?) ?? '',
      artistName: artist is Map<String, dynamic>
          ? (artist['name'] as String?) ?? ''
          : (json['artist_name'] as String?) ?? '',
      albumName: album is Map<String, dynamic>
          ? (album['name'] as String?) ?? ''
          : (json['album_name'] as String?) ?? '',
      genre: (json['genre'] as String?) ?? '',
      durationSeconds: _intOf(json['duration']),
      audioUrl: (json['audio'] as String?) ?? '',
      audioDownloadUrl: (json['audiodownload'] as String?) ?? '',
      licenseCcurl: (json['license_ccurl'] as String?) ?? '',
      image: (json['image'] as String?) ?? '',
    );
  }

  /// Jamendo track id (numeric string).
  final String id;

  /// Track title.
  final String name;

  /// Artist display name.
  final String artistName;

  /// Album display name.
  final String albumName;

  /// Genre tag when present.
  final String genre;

  /// Duration in seconds.
  final int durationSeconds;

  /// Streamable audio URL (`audio` field, mp32 stream).
  final String audioUrl;

  /// Downloadable audio URL (`audiodownload` field).
  final String audioDownloadUrl;

  /// License info page (CC link) for provenance sidecars.
  final String licenseCcurl;

  /// Album/track cover image URL.
  final String image;

  static int _intOf(Object? v) {
    if (v is int) {
      return v;
    }
    if (v is num) {
      return v.toInt();
    }
    if (v is String) {
      return int.tryParse(v) ?? 0;
    }
    return 0;
  }

  /// True when the entry can become a playable [Track].
  bool get isPlayable => id.isNotEmpty && name.isNotEmpty;
}

/// Jamendo provider ( Jamendo v3.0 REST API, CC-licensed catalog).
///
/// Requires an application `client_id` registered at developer.jamendo.com —
/// live-verified in the Stage 2.1 session that requests without a client_id
/// answer `status: failed, code 5`, and the historical demo id is suspended
/// (code 11). The id is supplied through [JamendoCredentials].
class JamendoSource implements SourceProvider {
  /// Creates the source; [limiter] enforces the 2 req/s API budget.
  JamendoSource({
    required this.clientId,
    Dio? dio,
    RateLimiter? limiter,
    DownloadFileExecutor? executor,
  })  : _dio = dio ?? Dio(),
        _executor = executor ?? IoDownloadFileExecutor(),
        limiter = limiter ??
            RateLimiter(const Duration(milliseconds: 500));

  /// Jamendo application client id (user-registered).
  final String clientId;

  /// Rate limiter (2 requests per second).
  final RateLimiter limiter;

  final Dio _dio;
  final DownloadFileExecutor _executor;

  @override
  String get id => sourceId;

  @override
  String get displayName => 'Jamendo';

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsDownload => true;

  @override
  bool get supportsSearch => true;

  /// Source identifier used for Jamendo-derived tracks.
  static const String sourceId = 'jamendo';

  /// Base URL of the Jamendo v3.0 API.
  static const String apiBase = 'https://api.jamendo.com/v3.0';

  /// Parses the shared response envelope; throws on `status: failed`.
  List<Map<String, dynamic>> _parseResults(Object? body) {
    if (body is! Map<String, dynamic>) {
      throw SourceApiException('jamendo: non-JSON response body');
    }
    final Object? headers = body['headers'];
    final bool ok = headers is Map<String, dynamic>
        ? headers['status'] == 'success'
        : false;
    if (!ok) {
      final String message = headers is Map<String, dynamic>
          ? (headers['error_message'] as String? ?? 'unknown Jamendo error')
          : 'unknown Jamendo error';
      throw SourceApiException('jamendo: $message');
    }
    final Object? results = body['results'];
    if (results is! List<dynamic>) {
      return const <Map<String, dynamic>>[];
    }
    return results.whereType<Map<String, dynamic>>().toList();
  }

  /// Maps one parsed result to the canonical [Track].
  Track toTrack(JamendoTrackResult r, {DateTime? addedAt}) {
    final DateTime stamp = addedAt ?? DateTime.now().toUtc();
    return Track(
      sourceId: sourceId,
      sourceTrackId: r.id,
      title: r.name,
      artist: r.artistName,
      album: r.albumName.isEmpty ? null : r.albumName,
      genre: r.genre.isEmpty ? null : r.genre,
      durationMs: r.durationSeconds * 1000,
      format: _formatOf(r.audioUrl),
      explicit: false,
      addedAt: stamp,
      updatedAt: stamp,
    );
  }

  String _formatOf(String url) {
    final Uri? uri = Uri.tryParse(url);
    final String path = uri?.path ?? '';
    final int dot = path.lastIndexOf('.');
    if (dot >= 0 && dot < path.length - 1) {
      return path.substring(dot + 1).toLowerCase();
    }
    return 'mp3';
  }

  @override
  Future<List<Track>> search(String q, {int limit = 20}) async {
    if (q.trim().isEmpty) {
      return const <Track>[];
    }
    await limiter.waitTurn();
    final Response<dynamic> res = await _dio.get<dynamic>(
      '$apiBase/tracks/',
      queryParameters: <String, dynamic>{
        'format': 'json',
        'limit': limit,
        'search': q.trim(),
        'client_id': clientId,
      },
    );
    return _parseResults(res.data)
        .map(JamendoTrackResult.fromJson)
        .where((JamendoTrackResult r) => r.isPlayable)
        .map(toTrack)
        .toList();
  }

  @override
  Future<StreamUrl> resolveStream(Track t) async {
    final Map<String, dynamic> raw = await getMetadata(t.sourceTrackId);
    final String url = (raw['audio'] as String?) ?? '';
    if (url.isEmpty) {
      throw SourceApiException('jamendo: no audio url for ${t.sourceTrackId}');
    }
    return StreamUrl(url: url);
  }

  @override
  Future<dynamic> download(
    Track t, {
    required String targetPath,
    required AudioQuality quality,
  }) async {
    final Map<String, dynamic> raw = await getMetadata(t.sourceTrackId);
    final String url = (raw['audiodownload'] as String?) ??
        (raw['audio'] as String?) ??
        '';
    if (url.isEmpty) {
      throw SourceApiException(
        'jamendo: no download url for ${t.sourceTrackId}',
      );
    }
    final int slash = targetPath.lastIndexOf('/');
    await _executor.ensureDir(
      slash <= 0 ? '/' : targetPath.substring(0, slash),
    );
    await _dio.download(url, targetPath);
    return _executor.fileAt(targetPath);
  }

  @override
  Future<Map<String, dynamic>> getMetadata(String sourceTrackId) async {
    await limiter.waitTurn();
    final Response<dynamic> res = await _dio.get<dynamic>(
      '$apiBase/tracks/',
      queryParameters: <String, dynamic>{
        'format': 'json',
        'id': sourceTrackId,
        'client_id': clientId,
      },
    );
    final List<Map<String, dynamic>> results = _parseResults(res.data);
    if (results.isEmpty) {
      throw SourceApiException(
        'jamendo: track $sourceTrackId not found',
      );
    }
    return results.first;
  }
}

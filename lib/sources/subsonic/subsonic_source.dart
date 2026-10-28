import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/source_file.dart';
import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/sources/download_file_exports.dart';
import 'package:wavely/sources/source_exception.dart';
import 'package:wavely/sources/subsonic/subsonic_config.dart';
import 'package:wavely/sources/subsonic/subsonic_mapper.dart';

/// Subsonic / Navidrome provider (Subsonic REST API v1.16.1).
///
/// Auth uses the salted MD5 token scheme (`t = md5(password + salt)`) so the
/// clear-text password never travels on the wire after the initial hash.
class SubsonicSource implements SourceProvider {
  /// Creates a source bound to [config]; [dio] and [executor] are injectable
  /// for contract tests, [mapper] for deterministic timestamps.
  SubsonicSource({
    required this.config,
    Dio? dio,
    DownloadFileExecutor? executor,
    SubsonicMapper? mapper,
  })  : _dio = dio ?? Dio(),
        _executor = executor ?? IoDownloadFileExecutor(),
        mapper = mapper ?? SubsonicMapper();

  /// Dio client (injectable for tests).
  final Dio _dio;

  /// File executor (io arm on real platforms; throws on web).
  final DownloadFileExecutor _executor;

  /// Child → Track mapper.
  final SubsonicMapper mapper;

  @override
  String get id => SubsonicMapper.sourceId;

  @override
  String get displayName => 'Subsonic';

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsDownload => true;

  @override
  bool get supportsSearch => true;

  /// Common auth + client query parameters (salted token auth).
  Map<String, String> _authParams({String? passwordOverride}) {
    final String salt = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final String password = passwordOverride ?? config.password;
    final String token = md5.convert(utf8.encode(password + salt)).toString();
    return <String, String>{
      'u': config.username,
      't': token,
      's': salt,
      'v': config.apiVersion,
      'c': SubsonicConfig.clientName,
      'f': 'json',
    };
  }

  Uri _endpoint(String path, Map<String, String> extra) {
    final Map<String, String> q = _authParams()..addAll(extra);
    return Uri.parse('${config.baseUrl}$path').replace(queryParameters: q);
  }

  /// Performs a REST call and returns the `subsonic-response` envelope.
  /// Throws [SourceApiException] on transport or protocol errors.
  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> extra,
  ) async {
    final Response<dynamic> res = await _dio.get<dynamic>(
      _endpoint(path, extra).toString(),
      options: Options(responseType: ResponseType.json),
    );
    final Object? data = res.data;
    if (data is! Map<String, dynamic>) {
      throw SourceApiException('unexpected response body type');
    }
    final Object? envelope = data['subsonic-response'];
    if (envelope is! Map<String, dynamic>) {
      throw SourceApiException('missing subsonic-response envelope');
    }
    if (envelope['status'] != 'ok') {
      final Object? err = envelope['error'];
      final String message = err is Map<String, dynamic>
          ? (err['message'] as String? ?? 'unknown error')
          : 'unknown error';
      throw SourceApiException(message);
    }
    return envelope;
  }

  /// Tests the connection (`ping.view`). Returns the server version when ok.
  Future<String> ping() async {
    final Map<String, dynamic> envelope = await _get('/rest/ping.view', const <String, String>{});
    return (envelope['version'] as String?) ?? config.apiVersion;
  }

  @override
  Future<List<Track>> search(String q, {int limit = 20}) async {
    if (q.trim().isEmpty) {
      return const <Track>[];
    }
    final Map<String, dynamic> envelope = await _get(
      '/rest/search3.view',
      <String, String>{'query': q.trim(), 'songCount': '$limit'},
    );
    final Object? result = envelope['searchResult3'];
    if (result is! Map<String, dynamic>) {
      return const <Track>[];
    }
    final Object? songs = result['song'];
    if (songs is! List<dynamic>) {
      return const <Track>[];
    }
    return mapper.fromChildList(songs);
  }

  @override
  Future<StreamUrl> resolveStream(Track t) async {
    final String direct = _endpoint(
      '/rest/stream.view',
      <String, String>{'id': t.sourceTrackId, 'format': 'raw'},
    ).toString();
    // Navidrome answers stream requests with a redirect carrying the real
    // (tokenised) file URL. Resolve it before handing the URL to the engine;
    // servers answering 200 directly are returned as-is. The GET uses a
    // stream response so a non-redirecting server does not buffer the audio.
    try {
      final Response<dynamic> res = await _dio.get<ResponseBody>(
        direct,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (int? code) => code != null && code < 400,
        ),
      );
      final String? location = res.headers.value('location');
      if (location != null && location.isNotEmpty) {
        return StreamUrl(url: Uri.parse(direct).resolve(location).toString());
      }
    } on DioException {
      // Fall through: many servers answer 200 with the bytes directly.
    }
    return StreamUrl(url: direct);
  }

  @override
  Future<File> download(
    Track t, {
    required String targetPath,
    required AudioQuality quality,
  }) async {
    final String url = _endpoint(
      '/rest/download.view',
      <String, String>{'id': t.sourceTrackId},
    ).toString();
    await _executor.ensureDir(parentDirOf(targetPath));
    await _dio.download(url, targetPath);
    return _executor.fileAt(targetPath);
  }

  @override
  Future<Map<String, dynamic>> getMetadata(String sourceTrackId) async {
    // `getSong.view` (Subsonic API 1.14+) returns the raw Child for one id.
    final Map<String, dynamic> envelope = await _get(
      '/rest/getSong.view',
      <String, String>{'id': sourceTrackId},
    );
    final Object? song = envelope['song'];
    if (song is! Map<String, dynamic>) {
      throw SourceApiException('song $sourceTrackId not found');
    }
    return song;
  }

  /// Parent directory of a forward-slash target path.
  static String parentDirOf(String path) {
    final int i = path.lastIndexOf('/');
    return i <= 0 ? '/' : path.substring(0, i);
  }

  /// Cover-art URL for [coverArtId] (already auth-stamped for image loading).
  String coverArtUrl(String coverArtId) =>
      _endpoint('/rest/getCoverArt.view', <String, String>{
        'id': coverArtId,
      }).toString();
}


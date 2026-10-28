import 'package:dio/dio.dart';
import 'package:wavely/data/remote/metadata_http.dart';

import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/source_file.dart';
import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/sources/download_file_exports.dart';
import 'package:wavely/sources/source_exception.dart';
import 'package:wavely/sources/subsonic/subsonic_source.dart';

/// One file entry of an archive.org item's `/metadata/{id}` response.
class ArchiveOrgFile {
  /// Creates a parsed file entry.
  const ArchiveOrgFile({
    required this.name,
    this.format = '',
    this.title = '',
    this.artist = '',
    this.track = '',
    this.lengthSeconds = 0,
    this.sizeBytes = 0,
  });

  /// Parses a `files[]` entry.
  factory ArchiveOrgFile.fromJson(Map<String, dynamic> json) =>
      ArchiveOrgFile(
        name: (json['name'] as String?) ?? '',
        format: (json['format'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        artist: json['artist'] is String
            ? json['artist'] as String
            : (json['artist'] is List
                ? (json['artist'] as List<dynamic>).join(', ')
                : ''),
        track: (json['track'] as String?) ?? '',
        lengthSeconds: _secondsOf(json['length']),
        sizeBytes: _intOf(json['size']),
      );

  /// File name inside the item (also the download path segment).
  final String name;

  /// archive.org format label (`Flac`, `VBR MP3`, `Ogg Vorbis`, ...).
  final String format;

  /// Per-file title when present.
  final String title;

  /// Per-file artist when present.
  final String artist;

  /// Track number label when present.
  final String track;

  /// Duration in seconds (archive.org reports `mm:ss` or plain seconds).
  final int lengthSeconds;

  /// File size in bytes.
  final int sizeBytes;

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

  static int _secondsOf(Object? v) {
    if (v is num) {
      return v.toInt();
    }
    if (v is String) {
      if (v.contains(':')) {
        final List<String> parts = v.split(':');
        var seconds = 0;
        for (final String p in parts) {
          seconds = seconds * 60 + (int.tryParse(p) ?? 0);
        }
        return seconds;
      }
      final double? d = double.tryParse(v);
      if (d != null) {
        return d.round();
      }
    }
    return 0;
  }

  /// File extension derived from [name].
  String get extension {
    final int dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) {
      return name.substring(dot + 1).toLowerCase();
    }
    return '';
  }

  /// True when the file is one of the audio formats Wavely plays.
  bool get isAudio {
    const Set<String> exts = <String>{'mp3', 'flac', 'ogg', 'oga', 'm4a', 'wav'};
    return exts.contains(extension);
  }
}

/// Parsed archive.org item (identifier + metadata + files).
class ArchiveOrgItem {
  /// Creates a parsed item.
  const ArchiveOrgItem({
    required this.identifier,
    this.title = '',
    this.creator = '',
    this.year = '',
    this.files = const <ArchiveOrgFile>[],
  });

  /// Identifier (URL-safe item key).
  final String identifier;

  /// Item title (album-level).
  final String title;

  /// Creator (artist-level); joined when archive.org returns a list.
  final String creator;

  /// Release year when present.
  final String year;

  /// Audio + auxiliary files of the item.
  final List<ArchiveOrgFile> files;

  /// Picks the best audio file per the Stage 2.1 quality preference:
  /// Flac > VBR MP3 > Ogg Vorbis > any other audio file.
  ArchiveOrgFile? get bestAudio {
    final List<ArchiveOrgFile> audio =
        files.where((ArchiveOrgFile f) => f.isAudio).toList();
    if (audio.isEmpty) {
      return null;
    }
    ArchiveOrgFile? pick(bool Function(String format) match) {
      for (final ArchiveOrgFile f in audio) {
        if (match(f.format.toLowerCase())) {
          return f;
        }
      }
      return null;
    }

    return pick((String f) => f.contains('flac')) ??
        pick((String f) => f.contains('vbr mp3') || f == 'mp3') ??
        pick((String f) => f.contains('ogg')) ??
        audio.first;
  }

  /// Direct file download URL for [file].
  String fileUrl(ArchiveOrgFile file) =>
      'https://archive.org/download/$identifier/'
      '${Uri.encodeComponent(file.name)}';
}

/// archive.org provider (public-domain and CC catalog, anonymous API).
///
/// Live-verified in the Stage 2.1 session: `advancedsearch.php` and
/// `/metadata/{id}` answer anonymously with JSON.
class ArchiveOrgSource implements SourceProvider {
  /// Creates the source; [limiter] defaults to ~2 req/s politeness.
  ArchiveOrgSource({
    Dio? dio,
    RateLimiter? limiter,
    DownloadFileExecutor? executor,
  })  : _dio = dio ?? Dio(),
        _executor = executor ?? IoDownloadFileExecutor(),
        limiter = limiter ?? RateLimiter(const Duration(milliseconds: 500));

  final Dio _dio;
  final DownloadFileExecutor _executor;

  /// Politeness limiter between API calls.
  final RateLimiter limiter;

  @override
  String get id => sourceId;

  @override
  String get displayName => 'archive.org';

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsDownload => true;

  @override
  bool get supportsSearch => true;

  /// Source identifier used for archive.org-derived tracks.
  static const String sourceId = 'archive';

  /// Separator joining identifier and file name inside
  /// [Track.sourceTrackId] (identifiers never contain `|`).
  static const String idSeparator = '|';

  @override
  Future<List<Track>> search(String q, {int limit = 20}) async {
    if (q.trim().isEmpty) {
      return const <Track>[];
    }
    await limiter.waitTurn();
    final Response<dynamic> res = await _dio.get<dynamic>(
      'https://archive.org/advancedsearch.php',
      queryParameters: <String, dynamic>{
        'q': '${q.trim()} AND mediatype:(audio)',
        'fl[]': const <String>['identifier', 'title', 'creator', 'year'],
        'rows': limit,
        'output': 'json',
        'page': 1,
      },
    );
    final Object? body = res.data;
    if (body is! Map<String, dynamic>) {
      throw const SourceApiException('archive.org: non-JSON search body');
    }
    final Object? response = body['response'];
    final Object? docsRaw = response is Map<String, dynamic>
        ? response['docs']
        : null;
    if (docsRaw is! List<dynamic>) {
      return const <Track>[];
    }
    final List<Track> out = <Track>[];
    for (final Object? doc in docsRaw) {
      if (doc is! Map<String, dynamic>) {
        continue;
      }
      final String identifier = (doc['identifier'] as String?) ?? '';
      if (identifier.isEmpty) {
        continue;
      }
      final ArchiveOrgItem item = await _fetchItem(identifier, doc: doc);
      final Track? track = _trackFromItem(item);
      if (track != null) {
        out.add(track);
      }
    }
    return out;
  }

  Future<ArchiveOrgItem> _fetchItem(
    String identifier, {
    Map<String, dynamic>? doc,
  }) async {
    await limiter.waitTurn();
    final Response<dynamic> res = await _dio
        .get<dynamic>('https://archive.org/metadata/$identifier');
    final Object? body = res.data;
    if (body is! Map<String, dynamic>) {
      throw SourceApiException('archive.org: non-JSON metadata for $identifier');
    }
    final Object? meta = body['metadata'];
    final Object? filesRaw = body['files'];
    final String title =
        (doc?['title'] as String?) ?? (meta is Map<String, dynamic> ? (meta['title'] as String?) ?? '' : '');
    final Object? creatorRaw = doc?['creator'] ?? (meta is Map<String, dynamic> ? meta['creator'] : null);
    final String creator = creatorRaw is List
        ? creatorRaw.join(', ')
        : (creatorRaw as String?) ?? '';
    final String year = _yearOf(
      doc?['year'] ?? (meta is Map<String, dynamic> ? meta['year'] : null),
    );
    final List<ArchiveOrgFile> files = (filesRaw as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ArchiveOrgFile.fromJson)
        .toList();
    return ArchiveOrgItem(
      identifier: identifier,
      title: title,
      creator: creator,
      year: year,
      files: files,
    );
  }

  String _yearOf(Object? v) => v == null ? '' : v.toString();

  /// Maps an item to one [Track] for its best audio file, or `null`.
  Track? _trackFromItem(ArchiveOrgItem item) {
    final ArchiveOrgFile? best = item.bestAudio;
    if (best == null) {
      return null;
    }
    final DateTime now = DateTime.now().toUtc();
    return Track(
      sourceId: sourceId,
      sourceTrackId: '${item.identifier}$idSeparator${best.name}',
      title: best.title.isNotEmpty ? best.title : item.title,
      artist: best.artist.isNotEmpty ? best.artist : item.creator,
      album: item.title.isEmpty ? null : item.title,
      durationMs: best.lengthSeconds * 1000,
      format: best.extension,
      explicit: false,
      addedAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<StreamUrl> resolveStream(Track t) async {
    final List<String> parts = t.sourceTrackId.split(idSeparator);
    if (parts.length != 2) {
      throw SourceApiException(
        'archive.org: malformed sourceTrackId ${t.sourceTrackId}',
      );
    }
    final String url =
        'https://archive.org/download/${parts[0]}/${Uri.encodeComponent(parts[1])}';
    return StreamUrl(url: url);
  }

  @override
  Future<dynamic> download(
    Track t, {
    required String targetPath,
    required AudioQuality quality,
  }) async {
    final StreamUrl stream = await resolveStream(t);
    await _executor.ensureDir(SubsonicSource.parentDirOf(targetPath));
    await _dio.download(stream.url, targetPath);
    return _executor.fileAt(targetPath);
  }

  @override
  Future<Map<String, dynamic>> getMetadata(String sourceTrackId) async {
    final List<String> parts = sourceTrackId.split(idSeparator);
    final String identifier = parts.first;
    await limiter.waitTurn();
    final Response<dynamic> res =
        await _dio.get<dynamic>('https://archive.org/metadata/$identifier');
    if (res.data is! Map<String, dynamic>) {
      throw SourceApiException(
        'archive.org: non-JSON metadata for $identifier',
      );
    }
    return res.data as Map<String, dynamic>;
  }
}

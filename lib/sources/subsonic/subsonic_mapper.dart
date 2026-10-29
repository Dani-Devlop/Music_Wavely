import 'package:wavely/domain/entities/entities.dart';

/// Parsed Subsonic REST `Child` element (a song in search3 / getAlbum
/// responses).
///
/// Hand-rolled parsing on purpose: no codegen surface for source adapters,
/// every field tolerant of missing keys (servers differ).
class SubsonicChild {
  /// Creates a parsed child element.
  const SubsonicChild({
    required this.id,
    required this.title,
    this.artist = '',
    this.album = '',
    this.genre = '',
    this.durationSeconds = 0,
    this.bitRate,
    this.suffix = '',
    this.contentType = '',
    this.size = 0,
    this.coverArtId,
    this.trackNumber,
    this.year,
    this.isDir = false,
    this.created,
  });

  /// Parses a `Child` (or `song`) JSON object.
  factory SubsonicChild.fromJson(Map<String, dynamic> json) => SubsonicChild(
        id: json['id']?.toString() ?? '',
        title: (json['title'] as String?) ?? (json['name'] as String?) ?? '',
        artist: (json['artist'] as String?) ?? '',
        album: (json['album'] as String?) ?? '',
        genre: (json['genre'] as String?) ?? '',
        durationSeconds: _intOf(json['duration']),
        bitRate: _intOf(json['bitRate']),
        suffix: (json['suffix'] as String?) ?? '',
        contentType: (json['contentType'] as String?) ?? '',
        size: _intOf(json['size']),
        coverArtId: json['coverArt']?.toString(),
        trackNumber: _intOf(json['track']),
        year: _intOf(json['year']),
        isDir: (json['isDir'] as bool?) ?? false,
        created: (json['created'] as String?),
      );

  /// Server-assigned id (`id` attribute).
  final String id;

  /// Song title.
  final String title;

  /// Artist display name.
  final String artist;

  /// Album display name.
  final String album;

  /// Genre tag, when present.
  final String genre;

  /// Duration in seconds (Subsonic unit).
  final int durationSeconds;

  /// Bitrate in kbps, when reported.
  final int? bitRate;

  /// File extension reported by the server (mp3, flac, ...).
  final String suffix;

  /// MIME content type, when reported.
  final String contentType;

  /// File size in bytes, when reported.
  final int size;

  /// Cover-art id usable with `getCoverArt.view`.
  final String? coverArtId;

  /// Track number inside the album, when reported.
  final int? trackNumber;

  /// Release year, when reported.
  final int? year;

  /// True for directory children (skipped by the mapper).
  final bool isDir;

  /// ISO-8601 creation timestamp string from the server.
  final String? created;

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

  /// True when this child can be mapped to a playable [Track].
  bool get isPlayable => !isDir && id.isNotEmpty && title.isNotEmpty;
}

/// Maps Subsonic `Child` JSON to the canonical [Track] entity.
class SubsonicMapper {
  /// Creates a mapper; [now] is injectable for deterministic tests.
  const SubsonicMapper({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Maps one child, or returns `null` for directories / unnamed entries.
  Track? fromChild(SubsonicChild child) {
    if (!child.isPlayable) {
      return null;
    }
    final DateTime stamp = _parseCreated(child.created) ?? _now();
    return Track(
      sourceId: SubsonicMapper.sourceId,
      sourceTrackId: child.id,
      title: child.title,
      artist: child.artist,
      album: child.album.isEmpty ? null : child.album,
      genre: child.genre.isEmpty ? null : child.genre,
      durationMs: child.durationSeconds * 1000,
      bitrate: child.bitRate,
      format: child.suffix.isEmpty
          ? _formatFromContentType(child.contentType)
          : child.suffix,
      explicit: false,
      addedAt: stamp,
      updatedAt: stamp,
    );
  }

  /// Maps a whole `song` list, skipping unparsable children.
  List<Track> fromChildList(List<dynamic> children) => children
      .whereType<Map<String, dynamic>>()
      .map(SubsonicChild.fromJson)
      .map(fromChild)
      .whereType<Track>()
      .toList();

  /// Source identifier used for every Subsonic-derived track.
  static const String sourceId = 'subsonic';

  DateTime? _parseCreated(String? iso) {
    if (iso == null || iso.isEmpty) {
      return null;
    }
    return DateTime.tryParse(iso)?.toUtc();
  }

  String _formatFromContentType(String contentType) {
    if (contentType.contains('flac')) {
      return 'flac';
    }
    if (contentType.contains('ogg')) {
      return 'ogg';
    }
    if (contentType.contains('mpeg') || contentType.contains('mp3')) {
      return 'mp3';
    }
    if (contentType.contains('wav')) {
      return 'wav';
    }
    return 'mp3';
  }
}

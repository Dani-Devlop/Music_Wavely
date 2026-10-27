import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wavely/core/extensions/duration_x.dart';
import 'package:wavely/core/extensions/string_x.dart';

part 'track.freezed.dart';

/// Canonical track entity shared by every layer (local files and remote
/// sources alike).
@freezed
abstract class Track with _$Track {
  const factory Track({
    int? id,
    required String sourceId,
    required String sourceTrackId,
    required String title,
    required String artist,
    String? album,
    String? genre,
    String? language,
    required int durationMs,
    int? bitrate,
    required String format,
    String? filePath,
    String? coverPath,
    @Default(false) bool explicit,
    required DateTime addedAt,
    required DateTime updatedAt,
    @Default(0) int playCount,
    DateTime? lastPlayedAt,
  }) = _Track;

  const Track._();

  /// [sourceId] of tracks that live in the local media library.
  static const String localSourceId = 'local';

  /// Human readable duration (`hmOrDash`); en dash when duration is unknown.
  String get displayDuration => Duration(milliseconds: durationMs).hmOrDash;

  /// Artist label with a fallback for blank metadata.
  String get artistOrUnknown => artist.isBlank ? 'Unknown Artist' : artist;

  /// True when the track belongs to the local (on-device) source.
  bool get isLocal => sourceId == localSourceId;
}

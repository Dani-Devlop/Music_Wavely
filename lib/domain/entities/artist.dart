import 'package:freezed_annotation/freezed_annotation.dart';

part 'artist.freezed.dart';

/// Artist aggregation of tracks (computed by grouping).
@freezed
abstract class Artist with _$Artist {
  const factory Artist({
    required String name,
    String? coverPath,
    required int trackCount,
    required int albumCount,
  }) = _Artist;
}

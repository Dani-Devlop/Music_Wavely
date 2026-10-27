import 'package:freezed_annotation/freezed_annotation.dart';

part 'album.freezed.dart';

/// Album aggregation of tracks (computed by grouping, not persisted 1:1).
@freezed
abstract class Album with _$Album {
  const factory Album({
    required String key,
    required String title,
    required String artist,
    String? coverPath,
    required int trackCount,
    required DateTime addedAt,
    int? year,
  }) = _Album;
}

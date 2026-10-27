import 'package:freezed_annotation/freezed_annotation.dart';

part 'playlist.freezed.dart';

/// User-curated playlist entity.
@freezed
abstract class Playlist with _$Playlist {
  const factory Playlist({
    int? id,
    required String name,
    String? description,
    String? coverPath,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default(0) int itemCount,
  }) = _Playlist;
}

import 'package:freezed_annotation/freezed_annotation.dart';

part 'play_event.freezed.dart';

/// One listening session of a track, used for stats and recommendations.
@freezed
abstract class PlayEvent with _$PlayEvent {
  const factory PlayEvent({
    int? id,
    required int trackId,
    required DateTime startedAt,
    required int listenedMs,
    @Default(false) bool completed,
    required String source,
    required String deviceId,
  }) = _PlayEvent;
}

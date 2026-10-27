import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wavely/domain/entities/track.dart';

part 'scan_events.freezed.dart';

/// Stream of events emitted by the library scanner.
@freezed
sealed class ScanEvent with _$ScanEvent {
  const factory ScanEvent.scanStarted({required String root}) = ScanStarted;

  const factory ScanEvent.trackFound({required Track track}) = TrackFound;

  const factory ScanEvent.progress({
    required int processed,
    required int total,
    required String currentFile,
  }) = ScanProgress;

  const factory ScanEvent.completed({
    required int count,
    required List<String> errors,
  }) = ScanCompleted;

  const factory ScanEvent.error({
    required String file,
    required String reason,
  }) = ScanError;

  const ScanEvent._();
}

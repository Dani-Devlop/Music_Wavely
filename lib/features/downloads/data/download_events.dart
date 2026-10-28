import 'package:wavely/data/local/db/tables/downloads.dart';

/// Emitted for every download lifecycle change (progress, status).
class DownloadEvent {
  /// Creates an event.
  const DownloadEvent({
    required this.rowId,
    required this.status,
    this.progress = 0,
    this.error,
  });

  /// Downloads row id.
  final int rowId;

  /// New status.
  final DownloadStatus status;

  /// Progress 0–100 (progress events only).
  final int progress;

  /// Failure reason (failed events only).
  final String? error;
}

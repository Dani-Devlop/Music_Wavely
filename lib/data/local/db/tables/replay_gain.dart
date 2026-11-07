import 'package:drift/drift.dart';

/// Per-track ReplayGain measurements (Phase 8.2).
///
/// One row per analyzed local track (`track_id` unique). Gains are stored
/// in dB as REALs; `peak` is the sample peak as a linear 0..1 value.
@DataClassName('ReplayGainRow', companion: 'ReplayGainCompanion')
class ReplayGainData extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Wavely `tracks.id` (local library rows).
  IntColumn get trackId => integer().unique()();

  /// Track gain in dB (negative = quieter than reference).
  RealColumn get trackGainDb => real()();

  /// Sample peak (linear, 0..1) used for clipping prevention.
  RealColumn get peak => real().nullable()();

  /// Album gain in dB, backfilled by an album pass (`null` until scanned
  /// as part of an album).
  RealColumn get albumGainDb => real().nullable()();

  /// ISO-8601 UTC timestamp of the scan.
  TextColumn get scannedAt => text()();
}

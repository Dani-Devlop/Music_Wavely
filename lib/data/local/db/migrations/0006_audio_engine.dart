import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/app_database.dart';

/// Phase 8 (audio engine): adds `replay_gain_data` (per-track
/// loudness/peak measurements) and `audio_profiles` (per-output-device
/// sound profiles).
abstract final class Migration0006 {
  /// Tables created by this migration.
  static const List<String> tableNames = <String>[
    'replay_gain_data',
    'audio_profiles',
  ];

  /// Runs the migration step.
  static Future<void> run(Migrator m, AppDatabase db) async {
    await m.createTable(db.replayGainData);
    await m.createTable(db.audioProfiles);
  }
}

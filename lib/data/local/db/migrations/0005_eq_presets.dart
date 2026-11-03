import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/app_database.dart';

/// Stage 4 (DAP feature 2.2): adds the `eq_presets` table for per-device
/// equalizer presets.
abstract final class Migration0005 {
  /// Tables created by this migration (documented contract, mirrors
  /// Migration0002).
  static const List<String> tableNames = <String>['eq_presets'];

  /// Runs the migration step.
  static Future<void> run(Migrator m, AppDatabase db) async {
    await m.createTable(db.eqPresets);
  }
}

import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/tables/eq_presets.dart';
import 'package:wavely/playback/equalizer/eq_presets.dart';

part 'eq_presets_dao.g.dart';

/// Persistence for per-device user equalizer presets (Stage 4, feature
/// 2.2).
///
/// The `(deviceId, name)` pair is UNIQUE (see `idx_eq_presets_device_name`),
/// so [upsert] is a true save-or-overwrite. All reads are fault-tolerant
/// the same way `NewsDao` is: malformed `bands_json` degrades to an empty
/// gain vector instead of throwing into the UI.
@DriftAccessor(tables: [EqPresets])
class EqPresetsDao extends DatabaseAccessor<AppDatabase>
    with _$EqPresetsDaoMixin {
  EqPresetsDao(super.attachedDatabase);

  /// Every preset stored for [deviceId], alphabetically by name.
  Future<List<EqPresetRow>> forDevice(String deviceId) {
    return (select(eqPresets)
          ..where((EqPresets row) => row.deviceId.equals(deviceId))
          ..orderBy([(EqPresets row) => OrderingTerm.asc(row.name)]))
        .get();
  }

  /// One preset by `(deviceId, name)`, or `null`.
  Future<EqPresetRow?> byName(String deviceId, String name) {
    return (select(eqPresets)
          ..where((EqPresets row) => row.deviceId.equals(deviceId))
          ..where((EqPresets row) => row.name.equals(name))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Saves (or overwrites) a preset. The gain vector is clamped and
  /// canonicalized through `EqualizerGains` before it hits storage, so the
  /// column always holds a valid JSON array.
  Future<void> upsert({
    required String deviceId,
    required String name,
    required List<double> gainsDb,
  }) async {
    final String now = DateTime.now().toUtc().toIso8601String();
    final EqPresetsCompanion entry = EqPresetsCompanion.insert(
      deviceId: deviceId,
      name: name,
      bandsJson: EqualizerGains.encode(EqualizerGains.clampAll(gainsDb)),
      createdAt: now,
      updatedAt: now,
    );
    await into(eqPresets).insert(
      entry,
      onConflict: DoUpdate(
        (_) => EqPresetsCompanion(
          bandsJson: entry.bandsJson,
          updatedAt: entry.updatedAt,
        ),
        target: <Column<Object>>[
          eqPresets.deviceId,
          eqPresets.name,
        ],
      ),
    );
  }

  /// Deletes the preset `(deviceId, name)`; returns the removed row count.
  Future<int> deleteByName(String deviceId, String name) {
    return (delete(eqPresets)
          ..where((EqPresets row) => row.deviceId.equals(deviceId))
          ..where((EqPresets row) => row.name.equals(name)))
        .go();
  }

  /// Removes every preset of [deviceId] (settings "reset EQ" hook).
  Future<int> clearDevice(String deviceId) {
    return (delete(eqPresets)
          ..where((EqPresets row) => row.deviceId.equals(deviceId)))
        .go();
  }
}

/// Helpers shared by the controller and tests for the `bands_json` column.
abstract final class EqPresetRowCodec {
  /// Decodes a row's gain vector; malformed values degrade to `[]`.
  static List<double> decode(EqPresetRow row) =>
      EqualizerGains.decode(row.bandsJson);
}

import 'package:drift/drift.dart';

/// A user-saved equalizer preset, scoped per device (Stage 4, feature 2.2).
///
/// `deviceId` is the stable per-install identifier produced by
/// `DeviceIdentity` (core/device/device_identity.dart), so the same sync
/// account can keep different curves per device (phone vs desktop).
@DataClassName('EqPresetRow', companion: 'EqPresetsCompanion')
@TableIndex(
  name: 'idx_eq_presets_device_name',
  unique: true,
  columns: {#deviceId, #name},
)
class EqPresets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get deviceId => text()();
  TextColumn get name => text()();
  TextColumn get bandsJson => text()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
}

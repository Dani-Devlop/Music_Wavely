import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/tables/audio_profiles.dart';

part 'audio_profiles_dao.g.dart';

/// Persistence for per-output-device audio profiles (Phase 8.4).
///
/// `(deviceKey, outputDeviceId)` is UNIQUE — upserts are true
/// save-or-overwrite.
@DriftAccessor(tables: [AudioProfiles])
class AudioProfilesDao extends DatabaseAccessor<AppDatabase>
    with _$AudioProfilesDaoMixin {
  AudioProfilesDao(super.attachedDatabase);

  /// Every profile stored for [deviceKey], alphabetically by output id.
  Future<List<AudioProfileRow>> forDevice(String deviceKey) {
    return (select(audioProfiles)
          ..where((AudioProfiles row) => row.deviceKey.equals(deviceKey))
          ..orderBy([(AudioProfiles row) => OrderingTerm.asc(row.outputDeviceId)]))
        .get();
  }

  /// One profile by `(deviceKey, outputDeviceId)`, or `null`.
  Future<AudioProfileRow?> byOutput(
    String deviceKey,
    String outputDeviceId,
  ) {
    return (select(audioProfiles)
          ..where((AudioProfiles row) => row.deviceKey.equals(deviceKey))
          ..where(
              (AudioProfiles row) => row.outputDeviceId.equals(outputDeviceId))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Full upsert over every profile column.
  Future<void> upsert({
    required String deviceKey,
    required String outputDeviceId,
    String label = '',
    required AudioProfileValues values,
  }) async {
    final String now = DateTime.now().toUtc().toIso8601String();
    final AudioProfilesCompanion entry = AudioProfilesCompanion.insert(
      deviceKey: deviceKey,
      outputDeviceId: outputDeviceId,
      label: Value(label),
      eqEnabled: Value(values.eqEnabled),
      eqGainsJson: Value(values.eqGainsJson),
      eqPresetKey: Value(values.eqPresetKey),
      bassBoost: Value(values.bassBoost),
      virtualizer: Value(values.virtualizer),
      reverbPreset: Value(values.reverbPreset),
      balance: Value(values.balance),
      forceMono: Value(values.forceMono),
      replayGainMode: Value(values.replayGainMode),
      replayGainPreampDb: Value(values.replayGainPreampDb),
      crossfadeSeconds: Value(values.crossfadeSeconds),
      gapless: Value(values.gapless),
      createdAt: now,
      updatedAt: now,
    );
    await into(audioProfiles).insert(
      entry,
      onConflict: DoUpdate(
        (_) => AudioProfilesCompanion(
          label: entry.label,
          eqEnabled: entry.eqEnabled,
          eqGainsJson: entry.eqGainsJson,
          eqPresetKey: entry.eqPresetKey,
          bassBoost: entry.bassBoost,
          virtualizer: entry.virtualizer,
          reverbPreset: entry.reverbPreset,
          balance: entry.balance,
          forceMono: entry.forceMono,
          replayGainMode: entry.replayGainMode,
          replayGainPreampDb: entry.replayGainPreampDb,
          crossfadeSeconds: entry.crossfadeSeconds,
          gapless: entry.gapless,
          updatedAt: entry.updatedAt,
        ),
        target: <Column<Object>>[
          audioProfiles.deviceKey,
          audioProfiles.outputDeviceId,
        ],
      ),
    );
  }

  /// Deletes the profile `(deviceKey, outputDeviceId)`; returns the removed
  /// row count.
  Future<int> deleteOutput(String deviceKey, String outputDeviceId) {
    return (delete(audioProfiles)
          ..where((AudioProfiles row) => row.deviceKey.equals(deviceKey))
          ..where(
              (AudioProfiles row) => row.outputDeviceId.equals(outputDeviceId)))
        .go();
  }
}

/// Raw column values of one profile row (codec-neutral input for
/// [AudioProfilesDao.upsert]).
class AudioProfileValues {
  const AudioProfileValues({
    this.eqEnabled = true,
    this.eqGainsJson = '[]',
    this.eqPresetKey = '',
    this.bassBoost = 0,
    this.virtualizer = 0,
    this.reverbPreset = '',
    this.balance = 0,
    this.forceMono = false,
    this.replayGainMode = 'off',
    this.replayGainPreampDb = 0,
    this.crossfadeSeconds = 0,
    this.gapless = true,
  });

  final bool eqEnabled;
  final String eqGainsJson;
  final String eqPresetKey;
  final int bassBoost;
  final int virtualizer;
  final String reverbPreset;
  final double balance;
  final bool forceMono;
  final String replayGainMode;
  final double replayGainPreampDb;
  final int crossfadeSeconds;
  final bool gapless;
}

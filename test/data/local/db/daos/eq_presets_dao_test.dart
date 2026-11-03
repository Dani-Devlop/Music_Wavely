/// Stage 4: EqPresetsDao CRUD, per-device scoping and unique-index upsert.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/playback/equalizer/eq_presets.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test('upsert inserts then overwrites by (deviceId, name)', () async {
    await db.eqPresetsDao.upsert(
      deviceId: 'dev-1',
      name: 'Warm',
      gainsDb: const <double>[2, 2, 1, 0, 0, 0, 0, 0, 0, 0],
    );
    await db.eqPresetsDao.upsert(
      deviceId: 'dev-1',
      name: 'Warm',
      gainsDb: const <double>[4, 3, 2, 1, 0, 0, 0, 0, 0, 0],
    );

    final List<EqPresetRow> rows = await db.eqPresetsDao.forDevice('dev-1');
    expect(rows, hasLength(1), reason: 'same key must overwrite, not append');
    expect(EqualizerGains.decode(rows.single.bandsJson).first, 4.0);
  });

  test('forDevice scopes strictly by deviceId', () async {
    await db.eqPresetsDao.upsert(
      deviceId: 'dev-1',
      name: 'Warm',
      gainsDb: const <double>[1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    );
    await db.eqPresetsDao.upsert(
      deviceId: 'dev-2',
      name: 'Warm',
      gainsDb: const <double>[-2, -2, -2, -2, -2, -2, -2, -2, -2, -2],
    );

    expect((await db.eqPresetsDao.forDevice('dev-1')).single.deviceId,
        'dev-1');
    expect(
      EqualizerGains
          .decode((await db.eqPresetsDao.forDevice('dev-2')).single.bandsJson)
          .first,
      -2.0,
    );
    expect(await db.eqPresetsDao.forDevice('dev-3'), isEmpty);
  });

  test('forDevice orders presets alphabetically by name', () async {
    for (final String name in const <String>['zeta', 'alpha', 'mid']) {
      await db.eqPresetsDao.upsert(
        deviceId: 'dev-1',
        name: name,
        gainsDb: const <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      );
    }
    final List<String> names =
        (await db.eqPresetsDao.forDevice('dev-1')).map((r) => r.name);
    expect(names, <String>['alpha', 'mid', 'zeta']);
  });

  test('byName returns null for unknown names/devices', () async {
    await db.eqPresetsDao.upsert(
      deviceId: 'dev-1',
      name: 'Warm',
      gainsDb: const <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    );
    expect(await db.eqPresetsDao.byName('dev-1', 'Warm'), isNotNull);
    expect(await db.eqPresetsDao.byName('dev-1', 'Nope'), isNull);
    expect(await db.eqPresetsDao.byName('dev-2', 'Warm'), isNull);
  });

  test('upsert clamps out-of-range gains before persisting', () async {
    await db.eqPresetsDao.upsert(
      deviceId: 'dev-1',
      name: 'Crazy',
      gainsDb: const <double>[-99, 99, 0, 0, 0, 0, 0, 0, 0, 0],
    );
    final EqPresetRow? row = await db.eqPresetsDao.byName('dev-1', 'Crazy');
    final List<double> gains = EqualizerGains.decode(row!.bandsJson);
    expect(gains[0], kEqMinGainDb);
    expect(gains[1], kEqMaxGainDb);
  });

  test('deleteByName removes only the matching row', () async {
    await db.eqPresetsDao.upsert(
      deviceId: 'dev-1',
      name: 'A',
      gainsDb: const <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    );
    await db.eqPresetsDao.upsert(
      deviceId: 'dev-1',
      name: 'B',
      gainsDb: const <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    );
    expect(await db.eqPresetsDao.deleteByName('dev-1', 'A'), 1);
    expect((await db.eqPresetsDao.forDevice('dev-1')).single.name, 'B');
    expect(await db.eqPresetsDao.deleteByName('dev-1', 'A'), 0);
  });

  test('clearDevice wipes the device but leaves others', () async {
    await db.eqPresetsDao.upsert(
      deviceId: 'dev-1',
      name: 'A',
      gainsDb: const <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    );
    await db.eqPresetsDao.upsert(
      deviceId: 'dev-2',
      name: 'B',
      gainsDb: const <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    );
    expect(await db.eqPresetsDao.clearDevice('dev-1'), 1);
    expect(await db.eqPresetsDao.forDevice('dev-1'), isEmpty);
    expect(await db.eqPresetsDao.forDevice('dev-2'), hasLength(1));
  });
}

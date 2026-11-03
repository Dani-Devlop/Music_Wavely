/// Stage 4: DeviceIdentity — stable per-install id over SettingsStore.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:wavely/core/device/device_identity.dart';
import 'package:wavely/core/settings/settings_store.dart';

void main() {
  group('DeviceIdentity.resolve', () {
    test('creates and persists a UUIDv4 on first call', () async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final DeviceIdentity identity = DeviceIdentity(store: store);

      final String id = await identity.resolve();

      expect(id, isNotEmpty);
      // UUIDv4 shape.
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(id),
        isTrue,
      );
      expect(await store.read<String>(kDeviceIdSettingsKey), id);
    });

    test('subsequent calls return the same id (cached)', () async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final DeviceIdentity identity = DeviceIdentity(store: store);
      final String first = await identity.resolve();
      expect(await identity.resolve(), first);
    });

    test('returns the persisted id when one already exists', () async {
      final InMemorySettingsStore store = InMemorySettingsStore(
        initial: <String, Object?>{kDeviceIdSettingsKey: 'existing-id'},
      );
      final DeviceIdentity identity = DeviceIdentity(
        store: store,
        idGenerator: () => 'should-not-be-used',
      );
      expect(await identity.resolve(), 'existing-id');
    });

    test('generator injection is honored for fresh ids', () async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final DeviceIdentity identity = DeviceIdentity(
        store: store,
        idGenerator: () => 'fixed-test-id',
      );
      expect(await identity.resolve(), 'fixed-test-id');
    });

    test('blank persisted ids are treated as missing', () async {
      final InMemorySettingsStore store = InMemorySettingsStore(
        initial: <String, Object?>{kDeviceIdSettingsKey: '   '},
      );
      final DeviceIdentity identity = DeviceIdentity(store: store);
      final String id = await identity.resolve();
      expect(id, isNot('   '));
      expect(await store.read<String>(kDeviceIdSettingsKey), id);
    });

    test('a failing store falls back to a session id without throwing',
        () async {
      final DeviceIdentity identity = DeviceIdentity(
        store: _ThrowingStore(),
        idGenerator: () => 'session-only',
      );
      expect(await identity.resolve(), 'session-only');
    });

    test('two identities over one store share the id (composition root '
        'semantics)', () async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final String a = await DeviceIdentity(store: store).resolve();
      final String b = await DeviceIdentity(store: store).resolve();
      expect(a, b);
    });
  });
}

/// Store whose every write explodes (simulates a broken persistence
/// layer).
class _ThrowingStore implements SettingsStore {
  @override
  Future<void> write(String key, Object? value) async {
    throw StateError('storage unavailable');
  }

  @override
  Future<T?> read<T>(String key) async {
    throw StateError('storage unavailable');
  }
}

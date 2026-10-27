/// Authored, awaiting local run (Task 2-a).
///
/// Tests for `lib/core/utils/platform_utils.dart` — the conditional-export
/// facade. The import below is the FACADE, so on the test host (Dart VM,
/// desktop OS) it resolves to the IO arm (`platform_utils_io.dart`) exactly
/// as a native build would.
///
/// Covered (host-testable, platform-independent surface):
/// - `DeviceInfoSnapshot` defaults and field carrying.
/// - `isLowEndDevice` — the pure heuristic, driven by injected
///   [DeviceInfoProvider] fakes (thresholds: RAM < 3072 MB; Android SDK <
///   29 with <= 4 cores, defaulting to 8 cores when unknown; failures and
///   null snapshots degrade to `false`).
/// - `PlatformUtils.isWeb` (always false on the VM) and the mutual
///   exclusivity of `isMobile` / `isDesktop` on a native host.
/// - `PlatformUtils.currentTargetPlatform` mirroring
///   `defaultTargetPlatform`.
/// - `defaultDeviceInfoProvider` resolving to `null` on desktop hosts (it
///   only queries device_info_plus on Android/iOS and web returns early).
///
/// NOT host-testable (needs real devices): the Android/iOS branches of
/// `defaultDeviceInfoProvider`.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/utils/platform_utils.dart';

void main() {
  group('DeviceInfoSnapshot', () {
    test('defaults every field to null', () {
      const snapshot = DeviceInfoSnapshot();
      expect(snapshot.totalRamMb, isNull);
      expect(snapshot.androidSdkInt, isNull);
      expect(snapshot.processorCount, isNull);
    });

    test('carries the provided values', () {
      const snapshot = DeviceInfoSnapshot(
        totalRamMb: 2048,
        androidSdkInt: 28,
        processorCount: 4,
      );
      expect(snapshot.totalRamMb, 2048);
      expect(snapshot.androidSdkInt, 28);
      expect(snapshot.processorCount, 4);
    });
  });

  group('isLowEndDevice (pure heuristic over an injected provider)', () {
    test('null snapshot → false (never blocks playback features)', () async {
      final low = await isLowEndDevice(provider: () async => null);
      expect(low, isFalse);
    });

    test('low RAM (< 3072 MB) → true', () async {
      final low = await isLowEndDevice(
        provider: () async => const DeviceInfoSnapshot(totalRamMb: 3071),
      );
      expect(low, isTrue);
    });

    test('RAM exactly at the threshold is NOT low-end', () async {
      final low = await isLowEndDevice(
        provider: () async => const DeviceInfoSnapshot(totalRamMb: 3072),
      );
      expect(low, isFalse);
    });

    test('ample RAM with a modern (or absent) sdkInt → false', () async {
      expect(
        await isLowEndDevice(
          provider: () async => const DeviceInfoSnapshot(
            totalRamMb: 8192,
            androidSdkInt: 33,
            processorCount: 2,
          ),
        ),
        isFalse,
      );
      expect(
        await isLowEndDevice(
          provider: () async => const DeviceInfoSnapshot(totalRamMb: 8192),
        ),
        isFalse,
      );
    });

    test('old Android with few cores → true', () async {
      expect(
        await isLowEndDevice(
          provider: () async => const DeviceInfoSnapshot(
            androidSdkInt: 28,
            processorCount: 4,
          ),
        ),
        isTrue,
      );
      expect(
        await isLowEndDevice(
          provider: () async => const DeviceInfoSnapshot(
            androidSdkInt: 21,
            processorCount: 2,
          ),
        ),
        isTrue,
      );
    });

    test('old Android but more than 4 cores → false', () async {
      expect(
        await isLowEndDevice(
          provider: () async => const DeviceInfoSnapshot(
            androidSdkInt: 28,
            processorCount: 5,
          ),
        ),
        isFalse,
      );
    });

    test('old Android with UNKNOWN cores uses the 8-core default → false',
        () async {
      expect(
        await isLowEndDevice(
          provider: () async =>
              const DeviceInfoSnapshot(androidSdkInt: 28),
        ),
        isFalse,
      );
    });

    test('new Android with few cores is not flagged by the age rule',
        () async {
      expect(
        await isLowEndDevice(
          provider: () async => const DeviceInfoSnapshot(
            androidSdkInt: 29,
            processorCount: 2,
          ),
        ),
        isFalse,
        reason: 'the core rule only fires for sdkInt < 29',
      );
    });

    test('a throwing provider degrades to false', () async {
      final low = await isLowEndDevice(
        provider: () async => throw StateError('device info unavailable'),
      );
      expect(low, isFalse);
    });

    test('falls back to the default provider when none is injected', () async {
      // On the desktop test host the default provider resolves to null
      // without touching device_info_plus (web returns early, desktop is
      // not Android/iOS).
      final low = await isLowEndDevice();
      expect(low, isFalse);
    });
  });

  group('defaultDeviceInfoProvider', () {
    test('resolves to null on desktop test hosts', () async {
      // The VM test host is a desktop OS (Linux/macOS/Windows) and not web,
      // so the provider hits its final `return null` without any plugin
      // call.
      final snapshot = await defaultDeviceInfoProvider();
      expect(snapshot, isNull);
    });
  });

  group('PlatformUtils facade', () {
    test('isWeb is false on the native test host', () {
      expect(PlatformUtils.isWeb, isFalse);
      expect(kIsWeb, isFalse, reason: 'sanity: the VM host is not web');
    });

    test('on a native host exactly one of isMobile / isDesktop holds', () {
      expect(PlatformUtils.isMobile, isNot(equals(PlatformUtils.isDesktop)));
    });

    test('isMobile/isDesktop agree with dart:io Platform', () {
      final expectedMobile =
          !kIsWeb && (Platform.isAndroid || Platform.isIOS);
      final expectedDesktop = !kIsWeb &&
          (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
      expect(PlatformUtils.isMobile, expectedMobile);
      expect(PlatformUtils.isDesktop, expectedDesktop);
    });

    test('currentTargetPlatform mirrors defaultTargetPlatform', () {
      expect(
        PlatformUtils.currentTargetPlatform,
        same(defaultTargetPlatform),
      );
    });
  });
}

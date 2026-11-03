/// Stage 4: Hi-Res audio policy + controller (fully injected — no
/// platform channels involved).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:wavely/playback/hires/hires_audio.dart';

void main() {
  group('HiResAudioPolicy.androidExclusiveSupported', () {
    test('null API level (off-Android) is not supported', () {
      expect(HiResAudioPolicy.androidExclusiveSupported(null), isFalse);
    });

    test('the boundary is exactly Android 14 (API 34)', () {
      expect(HiResAudioPolicy.androidExclusiveSupported(33), isFalse);
      expect(HiResAudioPolicy.androidExclusiveSupported(34), isTrue);
      expect(HiResAudioPolicy.androidExclusiveSupported(35), isTrue);
    });
  });

  group('HiResAudioController.enableAndroidExclusiveMode', () {
    test('below API 34 the activator is never called', () async {
      var activatorCalls = 0;
      final HiResAudioController controller = HiResAudioController(
        activator: () async {
          activatorCalls++;
          return true;
        },
        sdkIntProvider: () async => 33,
      );

      final HiResRequestResult result =
          await controller.enableAndroidExclusiveMode();

      expect(result.granted, isFalse);
      expect(activatorCalls, 0, reason: 'policy must gate before the call');
      expect(result.reason, contains('34'));
    });

    test('API 34 + granted activator succeeds', () async {
      var activatorCalls = 0;
      final HiResAudioController controller = HiResAudioController(
        activator: () async {
          activatorCalls++;
          return true;
        },
        sdkIntProvider: () async => 34,
      );

      final HiResRequestResult result =
          await controller.enableAndroidExclusiveMode();

      expect(result.granted, isTrue);
      expect(activatorCalls, 1);
    });

    test('API 34 + refused activator degrades to granted:false', () async {
      final HiResAudioController controller = HiResAudioController(
        activator: () async => false,
        sdkIntProvider: () async => 35,
      );

      final HiResRequestResult result =
          await controller.enableAndroidExclusiveMode();

      expect(result.granted, isFalse);
      expect(result.reason, contains('refused'));
    });

    test('a throwing activator never breaks the caller', () async {
      final HiResAudioController controller = HiResAudioController(
        activator: () async => throw StateError('binder exploded'),
        sdkIntProvider: () async => 34,
      );

      final HiResRequestResult result =
          await controller.enableAndroidExclusiveMode();

      expect(result.granted, isFalse);
      expect(result.reason, contains('failed'));
    });

    test('a throwing sdk provider is treated as unknown platform',
        () async {
      var activatorCalls = 0;
      final HiResAudioController controller = HiResAudioController(
        activator: () async {
          activatorCalls++;
          return true;
        },
        sdkIntProvider: () async => throw StateError('nope'),
      );

      final HiResRequestResult result =
          await controller.enableAndroidExclusiveMode();

      expect(result.granted, isFalse);
      expect(activatorCalls, 0);
    });

    test('null sdk (unknown platform) is rejected by the policy', () async {
      final HiResAudioController controller = HiResAudioController(
        activator: () async => true,
        sdkIntProvider: () async => null,
      );

      final HiResRequestResult result =
          await controller.enableAndroidExclusiveMode();

      expect(result.granted, isFalse);
      expect(result.reason, contains('unknown'));
    });
  });
}

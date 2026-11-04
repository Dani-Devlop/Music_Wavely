// Controller tests for lib/features/settings/data/update_providers.dart:
// the idle → checking → available/up-to-date → downloading → done/error
// state machine, driven entirely by a fake UpdateService (no network).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:wavely/features/settings/data/update_providers.dart';
import 'package:wavely/features/settings/data/update_service.dart';

import '../../support/fake_update_service.dart';

UpdateCheckResult _availableResult() => UpdateCheckResult.available(
      currentVersion: '1.0.0',
      latestVersion: 'v1.0.1',
      releaseUrl:
          'https://github.com/Dani-Devlop/Music_Wavely/releases/tag/v1.0.1',
      releaseNotes: 'Auto-update system',
      assetUrl: 'https://github.com/x/wavely.msix',
      assetName: 'wavely.msix',
      assetSizeBytes: 1048576,
    );

void main() {
  test('check() moves idle → available with the scripted result', () async {
    final container = ProviderContainer(
      overrides: [
        updateServiceProvider
            .overrideWithValue(FakeUpdateService(checkResult: _availableResult())),
      ],
    );
    addTearDown(container.dispose);

    final provider = updateFlowControllerProvider;
    expect(container.read(provider), isA<UpdateFlowIdle>());

    await container.read(provider.notifier).check();

    final UpdateFlowState state = container.read(provider);
    expect(state, isA<UpdateFlowAvailable>());
    final UpdateFlowAvailable available = state as UpdateFlowAvailable;
    expect(available.result.latestVersion, 'v1.0.1');
    expect(available.result.releaseNotes, 'Auto-update system');
    expect(available.result.assetUrl, isNotNull);
  });

  test('check() moves idle → up-to-date when no update exists', () async {
    final container = ProviderContainer(
      overrides: [
        updateServiceProvider.overrideWithValue(
          FakeUpdateService(checkResult: UpdateCheckResult.upToDate('1.0.0')),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(updateFlowControllerProvider.notifier).check();

    final UpdateFlowState state = container.read(updateFlowControllerProvider);
    expect(state, isA<UpdateFlowUpToDate>());
    expect((state as UpdateFlowUpToDate).version, '1.0.0');
  });

  test('startInstall() streams progress, then completes', () async {
    final gate = Completer<void>();
    final fake = FakeUpdateService(
      checkResult: _availableResult(),
      gate: gate,
    );
    final container = ProviderContainer(
      overrides: [updateServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    final provider = updateFlowControllerProvider;

    await container.read(provider.notifier).check();
    final List<UpdateFlowState> seen = <UpdateFlowState>[];
    container.listen(provider, (_, UpdateFlowState next) => seen.add(next));

    final Future<void> installDone =
        container.read(provider.notifier).startInstall();
    // Flush the synchronous progress emissions that happen before the
    // fake's gate.
    await Future<void>.delayed(Duration.zero);

    expect(container.read(provider), isA<UpdateFlowDownloading>());
    final UpdateFlowDownloading downloading =
        container.read(provider) as UpdateFlowDownloading;
    expect(downloading.received, 1048576);
    expect(downloading.total, 1048576);
    expect(
      seen.whereType<UpdateFlowDownloading>(),
      isNotEmpty,
      reason: 'progress states must be observable mid-flight',
    );

    gate.complete();
    await installDone;

    final UpdateFlowState done = container.read(provider);
    expect(done, isA<UpdateFlowDone>());
    expect((done as UpdateFlowDone).outcome, isA<UpdaterUiLaunched>());
    expect(fake.installCalls, 1);
  });

  test('failed installs surface InstallFailed without throwing', () async {
    final container = ProviderContainer(
      overrides: [
        updateServiceProvider.overrideWithValue(
          FakeUpdateService(
            checkResult: _availableResult(),
            outcome: const InstallFailed('disk full'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final provider = updateFlowControllerProvider;

    await container.read(provider.notifier).check();
    await container.read(provider.notifier).startInstall();

    final UpdateFlowState done = container.read(provider);
    expect(done, isA<UpdateFlowDone>());
    final UpdateFlowDone flowDone = done as UpdateFlowDone;
    expect(flowDone.outcome, isA<InstallFailed>());
    expect((flowDone.outcome as InstallFailed).message, 'disk full');
  });

  test('check failures degrade to the error state', () async {
    final container = ProviderContainer(
      overrides: [
        updateServiceProvider.overrideWithValue(ThrowingCheckService()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(updateFlowControllerProvider.notifier).check();

    final UpdateFlowState state = container.read(updateFlowControllerProvider);
    expect(state, isA<UpdateFlowError>());
  });

  test('startInstall() is a no-op outside the available state', () async {
    final fake = FakeUpdateService(checkResult: _availableResult());
    final container = ProviderContainer(
      overrides: [updateServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    // Idle state → no install is started.
    await container.read(updateFlowControllerProvider.notifier).startInstall();
    expect(fake.installCalls, 0);
  });
}

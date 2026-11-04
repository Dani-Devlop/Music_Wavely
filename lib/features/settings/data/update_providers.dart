import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:wavely/core/utils/link_launcher.dart';
import 'package:wavely/features/settings/data/update_installer.dart';
import 'package:wavely/features/settings/data/update_platform.dart';
import 'package:wavely/features/settings/data/update_service.dart';

part 'update_providers.g.dart';

/// GitHub-Releases update service bound to the platform installer
/// (real flows on IO platforms, browser fallback on web).
@Riverpod(keepAlive: true)
UpdateService updateService(Ref ref) => UpdateService(
      installer: createPlatformInstaller(
        linkLauncher: ref.watch(linkLauncherProvider),
      ),
    );

/// One-shot update check feeding the Settings row / nav badge. Runs once
/// per process (keepAlive) and degrades to `false` on every failure so a
/// rate-limited or offline check can never surface UI noise.
///
/// Hermetic in widget tests: the check is skipped entirely under
/// `flutter test` (override in tests that exercise the badge).
@Riverpod(keepAlive: true)
Future<bool> updateAvailableBadge(Ref ref) async {
  if (kIsWeb || runningInFlutterTest) {
    return false;
  }
  try {
    final result = await ref.watch(updateServiceProvider).checkForUpdate();
    return result.updateAvailable;
  } on Object {
    return false;
  }
}

/// Base class of the update-screen state machine (sealed — the screen's
/// `switch` is exhaustive over every phase).
sealed class UpdateFlowState {
  /// Creates the state.
  const UpdateFlowState();
}

/// Nothing has happened yet (the screen auto-triggers a check).
final class UpdateFlowIdle extends UpdateFlowState {
  /// Creates the state.
  const UpdateFlowIdle();
}

/// A GitHub check is in flight.
final class UpdateFlowChecking extends UpdateFlowState {
  /// Creates the state.
  const UpdateFlowChecking();
}

/// The running build is the newest published release.
final class UpdateFlowUpToDate extends UpdateFlowState {
  /// Creates the state.
  const UpdateFlowUpToDate(this.version);

  /// Version string of the running build.
  final String version;
}

/// A newer release exists and is ready to install.
final class UpdateFlowAvailable extends UpdateFlowState {
  /// Creates the state.
  const UpdateFlowAvailable(this.result);

  /// Full check result (notes, asset, release URL).
  final UpdateCheckResult result;
}

/// The platform asset is downloading (`total` is `null` when unknown).
final class UpdateFlowDownloading extends UpdateFlowState {
  /// Creates the state.
  const UpdateFlowDownloading({
    required this.result,
    required this.received,
    this.total,
  });

  /// Release being downloaded.
  final UpdateCheckResult result;

  /// Bytes received so far.
  final int received;

  /// Total bytes when the server advertises a length.
  final int? total;
}

/// The asset is downloaded; the platform installer is taking over.
final class UpdateFlowInstalling extends UpdateFlowState {
  /// Creates the state.
  const UpdateFlowInstalling(this.result);

  /// Release handed to the installer.
  final UpdateCheckResult result;
}

/// The install attempt reached a terminal, presentable outcome.
final class UpdateFlowDone extends UpdateFlowState {
  /// Creates the state.
  const UpdateFlowDone({required this.outcome, required this.result});

  /// What happened (updater UI launched, AppImage replaced, release page
  /// opened, or a failure message).
  final UpdateInstallOutcome outcome;

  /// Release that was installed (or surfaced).
  final UpdateCheckResult result;
}

/// The check or install failed with a presentable [message].
final class UpdateFlowError extends UpdateFlowState {
  /// Creates the state.
  const UpdateFlowError(this.message, {this.result});

  /// Human-readable failure description.
  final String message;

  /// Result when the failure happened after a successful check.
  final UpdateCheckResult? result;
}

/// Drives the update screen: check → (install with progress) → done.
/// All platform work goes through [updateServiceProvider], which tests
/// override with a fake — no network ever leaves the widget tests.
@riverpod
class UpdateFlowController extends _$UpdateFlowController {
  @override
  UpdateFlowState build() => const UpdateFlowIdle();

  /// Runs the GitHub check and moves to up-to-date / available / error.
  Future<void> check() async {
    state = const UpdateFlowChecking();
    try {
      final result = await ref.read(updateServiceProvider).checkForUpdate();
      if (!result.updateAvailable) {
        state = UpdateFlowUpToDate(result.currentVersion);
        return;
      }
      state = UpdateFlowAvailable(result);
    } on Object catch (error) {
      state = UpdateFlowError('Update check failed: $error');
    }
  }

  /// Starts the platform install flow, streaming download progress into
  /// the state machine.
  Future<void> startInstall() async {
    final current = state;
    if (current is! UpdateFlowAvailable) {
      return;
    }
    final result = current.result;
    state = UpdateFlowDownloading(result: result, received: 0);
    try {
      final outcome = await ref.read(updateServiceProvider).install(
        result,
        onProgress: (received, total) {
          state = UpdateFlowDownloading(
            result: result,
            received: received,
            total: total,
          );
        },
      );
      state = UpdateFlowDone(outcome: outcome, result: result);
    } on Object catch (error) {
      state = UpdateFlowError('Update failed: $error', result: result);
    }
  }

  /// Opens the GitHub release page in the external browser (fallback
  /// action available from every state).
  Future<void> openReleasePage() async {
    final current = state;
    final url = current is UpdateFlowAvailable
        ? current.result.releaseUrl
        : current is UpdateFlowDone
            ? current.result.releaseUrl
            : current is UpdateFlowError
                ? current.result?.releaseUrl
                : null;
    await ref.read(linkLauncherProvider).launchExternal(
          Uri.parse(url ?? UpdateService.releasesPage),
        );
  }
}

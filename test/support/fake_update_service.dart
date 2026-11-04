import 'dart:async';

import 'package:wavely/features/settings/data/update_service.dart';

/// Canned [UpdateService] for controller/screen tests: returns a scripted
/// check result, optionally gates the install behind a [Completer] (so
/// tests can assert mid-download states) and records install calls.
///
/// No HTTP client is ever touched — the base constructor only allocates
/// one, and every network method is overridden.
class FakeUpdateService extends UpdateService {
  /// Creates the fake.
  FakeUpdateService({
    required this.checkResult,
    this.outcome = const UpdaterUiLaunched(),
    this.gate,
  }) : super(currentVersion: '0.1.0');

  /// Result served by [checkForUpdate].
  final UpdateCheckResult checkResult;

  /// Outcome served by [install] (after [gate] resolves).
  final UpdateInstallOutcome outcome;

  /// When set, [install] awaits this completer before returning.
  final Completer<void>? gate;

  /// Number of install invocations.
  int installCalls = 0;

  @override
  Future<UpdateCheckResult> checkForUpdate() async => checkResult;

  @override
  Future<UpdateInstallOutcome> install(
    UpdateCheckResult result, {
    UpdateProgressCallback? onProgress,
  }) async {
    installCalls++;
    onProgress?.call(0, 1048576);
    onProgress?.call(1048576, 1048576);
    if (gate != null) {
      await gate!.future;
    }
    return outcome;
  }
}

/// [UpdateService] whose check always throws (error-path tests).
class ThrowingCheckService extends UpdateService {
  /// Creates the fake.
  ThrowingCheckService() : super(currentVersion: '0.1.0');

  @override
  Future<UpdateCheckResult> checkForUpdate() async {
    throw StateError('offline');
  }
}

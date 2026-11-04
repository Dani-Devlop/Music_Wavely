import 'package:wavely/core/utils/link_launcher.dart';
import 'package:wavely/features/settings/data/update_service.dart';

/// Web build of the installer: nothing is installable inside a browser,
/// so every install attempt degrades to opening the GitHub release page
/// in the external browser.
final class WebUpdateInstaller implements UpdateInstaller {
  /// Creates the web installer over [launcher].
  const WebUpdateInstaller(LinkLauncher launcher) : _launcher = launcher;

  final LinkLauncher _launcher;

  @override
  Future<UpdateInstallOutcome> install(
    UpdateCheckResult result, {
    UpdateProgressCallback? onProgress,
  }) async {
    final url = Uri.parse(result.releaseUrl ?? UpdateService.releasesPage);
    await _launcher.launchExternal(url);
    return const OpenedReleasePage();
  }
}

/// Builds the platform update installer (web variant: browser fallback).
UpdateInstaller createPlatformInstaller({LinkLauncher? linkLauncher}) =>
    WebUpdateInstaller(linkLauncher ?? const UrlLinkLauncher());

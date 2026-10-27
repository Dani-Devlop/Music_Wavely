import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens external https links (GitHub tile) outside the app.
///
/// The indirection exists purely for tests: the settings screen depends on
/// [linkLauncherProvider], unit tests override it with a recording fake so
/// no platform channel is ever invoked (url_launcher's static API is not
/// directly mockable — https://pub.dev/packages/url_launcher#api).
abstract interface class LinkLauncher {
  /// Launches [url] with the platform default browser. Returns `false` when
  /// the platform reports it cannot handle the link (no exception is
  /// thrown for the common "nothing can open this" case).
  Future<bool> launchExternal(Uri url);
}

/// Production binding over `url_launcher` 6.3.x.
///
/// `LaunchMode.externalApplication` keeps Wavely one-tap-and-out: https
/// links need no per-app queries on Android 11+ and never open an in-app
/// web view.
final class UrlLinkLauncher implements LinkLauncher {
  /// Creates the launcher.
  const UrlLinkLauncher();

  @override
  Future<bool> launchExternal(Uri url) => launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
}

/// Composition binding; tests override with a fake.
final linkLauncherProvider = Provider<LinkLauncher>(
  (ref) => const UrlLinkLauncher(),
);

/// Wavely plugin contract (Stage 4, DAP feature 2.3).
///
/// **Security model — read before adding capabilities:**
///
/// Plugins in Wavely are *compiled-in* integrations, not dynamically
/// loaded code. There is deliberately NO mechanism to:
/// - load native shared libraries at runtime,
/// - download and evaluate Dart/JS code,
/// - grant access to the raw process, database or credential stores.
///
/// A plugin only ever sees a [PluginHostContext] — a narrow registrar
/// surface the host controls. Everything a plugin can do is declared up
/// front in its [PluginManifest.capabilities]. Future extensions of the
/// surface MUST keep this property: capability-declared, sandboxed,
/// host-mediated (the host stays free to refuse or drop registrations).
library;

import 'package:wavely/domain/repositories/source_provider.dart';

/// What a plugin is allowed to do (declared in its manifest).
enum PluginCapability {
  /// Contributes [SourceProvider]s (streaming / search sources).
  source,

  /// Enriches track metadata (future surface — not handed out yet).
  metadata,

  /// Contributes lyrics providers (future surface — not handed out yet).
  lyrics,
}

/// Immutable identity + capability declaration of a plugin.
class PluginManifest {
  /// Creates the manifest.
  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.capabilities,
    this.description = '',
  });

  /// Stable plugin id (dot-namespaced, e.g. `plugin.local-folder`).
  final String id;

  /// Human-readable name for the UI.
  final String name;

  /// Semver-ish version string.
  final String version;

  /// Declared capabilities — the host enforces this list.
  final List<PluginCapability> capabilities;

  /// One-line description.
  final String description;
}

/// The sandboxed surface a plugin receives at init time.
///
/// This is the ONLY object a plugin gets; the host keeps full control over
/// what a registration actually does (and may ignore it).
abstract class PluginHostContext {
  /// Registers a [SourceProvider] contributed by the calling plugin.
  /// The host owns the resulting collection.
  void registerSource(SourceProvider source);
}

/// A Wavely plugin (see the library doc for the security model).
abstract class WavelyPlugin {
  /// Immutable identity/capability declaration.
  PluginManifest get manifest;

  /// Called once by the [PluginHost] before the plugin is used. May throw;
  /// a throwing init only fails that plugin (host isolates the failure).
  Future<void> init(PluginHostContext context);

  /// Called on host shutdown. Implementations must be idempotent.
  Future<void> dispose();
}

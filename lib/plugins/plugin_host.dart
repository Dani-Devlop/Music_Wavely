/// Plugin host / registry (Stage 4, DAP feature 2.3).
///
/// Owns the lifecycle of the bundled plugins and the sources they
/// contribute. See `plugin_api.dart` for the security model — the host is
/// the enforcement point: it instantiates only compile-time-registered
/// factories, isolates every `init`/`dispose` failure, and owns the
/// contributed [SourceProvider] collection.
library;

import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/plugins/plugin_api.dart';

/// Factory signature used by the host's compile-time plugin list.
typedef WavelyPluginFactory = WavelyPlugin Function();

/// Outcome of loading one plugin.
class PluginLoadResult {
  /// Creates a success result.
  const PluginLoadResult.ok(PluginManifest this.manifest)
      : error = null;

  /// Creates a failure result ([manifest] is the declared manifest when
  /// known, `null` when the plugin could not even be instantiated).
  const PluginLoadResult.failed(this.error, [this.manifest]);

  /// The plugin manifest (when known).
  final PluginManifest? manifest;

  /// Failure description, `null` on success.
  final String? error;

  /// Whether the plugin loaded cleanly.
  bool get ok => error == null;
}

/// Loads, isolates and disposes the bundled plugins.
class PluginHost {
  /// Creates the host over compile-time [factories] (one per bundled
  /// plugin).
  PluginHost({required List<WavelyPluginFactory> factories})
      : _factories = List<WavelyPluginFactory>.of(factories);

  final List<WavelyPluginFactory> _factories;
  final List<WavelyPlugin> _loaded = <WavelyPlugin>[];
  final List<SourceProvider> _sources = <SourceProvider>[];
  bool _disposed = false;

  /// Declared manifests of every bundled plugin (without loading them).
  List<PluginManifest> describeBundled() => <PluginManifest>[
        for (final WavelyPluginFactory factory in _factories) factory().manifest,
      ];

  /// Plugins that finished `init` successfully, in load order.
  List<PluginManifest> get loadedManifests => <PluginManifest>[
        for (final WavelyPlugin plugin in _loaded) plugin.manifest,
      ];

  /// Sources contributed by loaded plugins, in registration order.
  List<SourceProvider> get registeredSources =>
      List<SourceProvider>.unmodifiable(_sources);

  /// Loads every bundled plugin, isolating failures: one throwing `init`
  /// never prevents the others from loading. Returns one result per
  /// factory, in the same order.
  Future<List<PluginLoadResult>> loadAll() async {
    final List<PluginLoadResult> results = <PluginLoadResult>[];
    for (final WavelyPluginFactory factory in _factories) {
      WavelyPlugin? plugin;
      try {
        plugin = factory();
      } on Object catch (e) {
        results.add(PluginLoadResult.failed('instantiate: $e'));
        continue;
      }
      try {
        await plugin.init(_PluginHostContext._(this));
        _loaded.add(plugin);
        results.add(PluginLoadResult.ok(plugin.manifest));
      } on Object catch (e) {
        results.add(PluginLoadResult.failed('init: $e', plugin.manifest));
      }
    }
    return results;
  }

  /// Disposes every loaded plugin (failures isolated, mirrors [loadAll])
  /// and drops all registrations. Idempotent.
  Future<void> disposeAll() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final WavelyPlugin plugin in List<WavelyPlugin>.of(_loaded)) {
      try {
        await plugin.dispose();
      } on Object {
        // A misbehaving plugin must not break host shutdown.
      }
    }
    _loaded.clear();
    _sources.clear();
  }
}

/// The one [PluginHostContext] implementation — a private adapter so
/// plugins can never downcast to [PluginHost] itself.
class _PluginHostContext implements PluginHostContext {
  _PluginHostContext._(this._host);

  final PluginHost _host;

  @override
  void registerSource(SourceProvider source) {
    _host._sources.add(source);
  }
}

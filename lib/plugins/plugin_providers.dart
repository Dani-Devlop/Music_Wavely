import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/plugins/bundled/local_folder_plugin.dart';
import 'package:wavely/plugins/plugin_host.dart';

/// Manual provider (plugin layer keeps no codegen surface): the
/// compile-time bundled plugin list.
///
/// The host is NOT auto-loaded at bootstrap — loading is an explicit,
/// caller-owned step (settings / future plugin screen) so app startup
/// stays side-effect free. The mock plugin starts with an empty folder
/// list; the owner UI fills it later.
final pluginHostProvider = Provider<PluginHost>((ref) {
  final PluginHost host = PluginHost(
    factories: <WavelyPluginFactory>[
      () => LocalFolderPlugin(folders: const <String>[]),
    ],
  );
  ref.onDispose(host.disposeAll);
  return host;
});

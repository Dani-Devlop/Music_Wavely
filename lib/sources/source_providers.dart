import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/sources/source_registry.dart';

/// Riverpod wiring for the Stage 2.1 sources (manual providers — no codegen
/// surface for the sources layer).

/// Settings + credentials persistence for the online sources.
final sourceSettingsProvider = Provider<SourceSettings>((ref) {
  return SourceSettings(ref.watch(sharedPrefsProvider));
});

/// Registry building SourceProvider instances from [sourceSettingsProvider].
final sourceRegistryProvider = Provider<SourceRegistry>((ref) {
  return SourceRegistry(ref.watch(sourceSettingsProvider));
});

/// Descriptors for the settings UI rows (id, name, configured, enabled).
final sourceDescriptorsProvider =
    FutureProvider<List<SourceDescriptor>>((ref) async {
  return ref.watch(sourceRegistryProvider).describeAll();
});

/// Every configured + enabled source. The settings UI calls
/// `ref.invalidate(enabledSourcesProvider)` after add/edit/remove/enable
/// changes.
final enabledSourcesProvider =
    FutureProvider<List<SourceProvider>>((ref) async {
  return ref.watch(sourceRegistryProvider).resolveEnabled();
});

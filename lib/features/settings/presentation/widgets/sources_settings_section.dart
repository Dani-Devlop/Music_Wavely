import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/settings/presentation/widgets/subsonic_config_sheet.dart';
import 'package:wavely/sources/source_registry.dart';
import 'package:wavely/sources/subsonic/subsonic_config.dart';
import 'package:wavely/sources/source_providers.dart';

/// Settings section listing every Stage 2.1 online source with an
/// enable/disable switch, an edit/add action and (for Subsonic) a
/// "Test connection" entry point.
///
/// Additive: rendered as one widget inserted into the existing settings
/// ListView; the Jamendo client-id row opens a small dialog.
class SourcesSettingsSection extends ConsumerWidget {
  /// Creates the section.
  const SourcesSettingsSection({super.key});

  Future<void> _editJamendo(BuildContext context, WidgetRef ref) async {
    final SourceSettings settings = ref.read(sourceSettingsProvider);
    final TextEditingController controller =
        TextEditingController(text: settings.loadJamendoClientId() ?? '');
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Jamendo client id'),
        content: TextField(
          key: const Key('jamendo-clientid-field'),
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Register at developer.jamendo.com',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('jamendo-save-button'),
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      await settings.saveJamendoClientId(result);
      ref.invalidate(enabledSourcesProvider);
      ref.invalidate(sourceDescriptorsProvider);
    }
    controller.dispose();
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    SourceDescriptor d,
  ) async {
    if (d.id == subsonicId) {
      final SubsonicConfig? existing =
          await ref.read(sourceSettingsProvider).loadSubsonic();
      if (context.mounted) {
        await SubsonicConfigSheet.show(context, existing: existing);
      }
      return;
    }
    if (d.id == jamendoSourceId) {
      await _editJamendo(context, ref);
    }
    // archive.org and FMA need no configuration — no editor.
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final AsyncValue<List<SourceDescriptor>> descriptors =
        ref.watch(sourceDescriptorsProvider);
    final List<SourceDescriptor> rows =
        descriptors.asData?.value ?? const <SourceDescriptor>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (rows.isEmpty)
          Text(
            'Loading sources…',
            style: TextStyle(color: colors.textTertiary),
          )
        else
          ...rows.map(
            (SourceDescriptor d) => ListTile(
              key: Key('source-row-${d.id}'),
              title: Text(
                d.displayName,
                style: TextStyle(color: colors.textPrimary),
              ),
              subtitle: Text(
                d.configured ? 'Configured' : 'Not configured',
                style: TextStyle(color: colors.textTertiary),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Switch(
                    key: Key('source-switch-${d.id}'),
                    value: d.enabled,
                    onChanged: (bool v) async {
                      await ref
                          .read(sourceSettingsProvider)
                          .setSourceEnabled(d.id, v);
                      ref.invalidate(enabledSourcesProvider);
                      ref.invalidate(sourceDescriptorsProvider);
                    },
                  ),
                  if (d.id == subsonicId || d.id == jamendoSourceId)
                    IconButton(
                      key: Key('source-edit-${d.id}'),
                      tooltip: 'Configure',
                      icon: const Icon(Icons.settings_rounded),
                      onPressed: () => _openEditor(context, ref, d),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

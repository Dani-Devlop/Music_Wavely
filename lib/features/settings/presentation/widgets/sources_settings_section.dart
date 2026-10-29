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
class SourcesSettingsSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const SourcesSettingsSection({super.key});

  @override
  ConsumerState<SourcesSettingsSection> createState() =>
      _SourcesSettingsSectionState();
}

class _SourcesSettingsSectionState
    extends ConsumerState<SourcesSettingsSection> {
  /// Optimistic toggle overlay: set synchronously on change so the switch
  /// reflects the new value immediately while the descriptor provider
  /// refreshes asynchronously in the background.
  final Map<String, bool> _optimistic = <String, bool>{};

  Future<void> _editJamendo() async {
    final SourceSettings settings = ref.read(sourceSettingsProvider);
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) =>
          _JamendoClientIdDialog(initial: settings.loadJamendoClientId()),
    );
    if (result != null) {
      await settings.saveJamendoClientId(result);
      ref.invalidate(enabledSourcesProvider);
      ref.invalidate(sourceDescriptorsProvider);
    }
  }

  Future<void> _openEditor(SourceDescriptor d) async {
    if (d.id == subsonicId) {
      final SubsonicConfig? existing =
          await ref.read(sourceSettingsProvider).loadSubsonic();
      if (mounted) {
        await SubsonicConfigSheet.show(context, existing: existing);
      }
      return;
    }
    if (d.id == jamendoSourceId) {
      await _editJamendo();
    }
    // archive.org and FMA need no configuration — no editor.
  }

  @override
  Widget build(BuildContext context) {
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
                    value: _optimistic[d.id] ?? d.enabled,
                    onChanged: (bool v) async {
                      // Optimistic: reflect the new state on the next frame,
                      // before the async descriptor refresh completes.
                      setState(() => _optimistic[d.id] = v);
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
                      onPressed: () => _openEditor(d),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Jamendo client-id dialog. Owns its [TextEditingController] so the
/// controller is disposed exactly when the dialog subtree unmounts (end of
/// the pop animation) — disposing it from the caller after async saves
/// raced the route's exit animation and crashed rebuilds with
/// "used after being disposed".
class _JamendoClientIdDialog extends StatefulWidget {
  const _JamendoClientIdDialog({required this.initial});

  final String? initial;

  @override
  State<_JamendoClientIdDialog> createState() => _JamendoClientIdDialogState();
}

class _JamendoClientIdDialogState extends State<_JamendoClientIdDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Jamendo client id'),
      content: TextField(
        key: const Key('jamendo-clientid-field'),
        controller: _controller,
        decoration: const InputDecoration(
          hintText: 'Register at developer.jamendo.com',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('jamendo-save-button'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

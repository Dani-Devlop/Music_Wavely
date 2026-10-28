import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/sources/source_providers.dart';
import 'package:wavely/sources/subsonic/subsonic_config.dart';
import 'package:wavely/sources/subsonic/subsonic_source.dart';

/// Modal sheet to add/edit the Subsonic/Navidrome connection.
///
/// URL + username + password fields and a "Test connection" button that
/// runs [SubsonicSource.ping]. Save persists public fields to
/// SharedPreferences and the password to the credential store.
class SubsonicConfigSheet extends ConsumerStatefulWidget {
  /// Creates the sheet; [existing] loads current values when editing.
  const SubsonicConfigSheet({super.key, this.existing});

  final SubsonicConfig? existing;

  /// Convenience opener.
  static Future<void> show(BuildContext context, {SubsonicConfig? existing}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (BuildContext _) =>
            SubsonicConfigSheet(existing: existing),
      );

  @override
  ConsumerState<SubsonicConfigSheet> createState() =>
      _SubsonicConfigSheetState();
}

class _SubsonicConfigSheetState extends ConsumerState<SubsonicConfigSheet> {
  late final TextEditingController _url =
      TextEditingController(text: widget.existing?.url ?? '');
  late final TextEditingController _username =
      TextEditingController(text: widget.existing?.username ?? '');
  late final TextEditingController _password =
      TextEditingController(text: widget.existing?.password ?? '');

  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final SubsonicSource probe = SubsonicSource(
        config: SubsonicConfig(
          url: _url.text,
          username: _username.text,
          password: _password.text,
        ),
      );
      final String version = await probe.ping();
      setState(() {
        _testOk = true;
        _testResult = 'Connected (server API $version)';
      });
    } on Object catch (e) {
      setState(() {
        _testOk = false;
        _testResult = 'Failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  Future<void> _save() async {
    final SourceSettings settings = ref.read(sourceSettingsProvider);
    await settings.saveSubsonic(
      SubsonicConfig(
        url: _url.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
      ),
    );
    ref.invalidate(enabledSourcesProvider);
    ref.invalidate(sourceDescriptorsProvider);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _remove() async {
    final SourceSettings settings = ref.read(sourceSettingsProvider);
    await settings.clearSubsonic();
    ref.invalidate(enabledSourcesProvider);
    ref.invalidate(sourceDescriptorsProvider);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Subsonic / Navidrome',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            key: const Key('subsonic-url-field'),
            controller: _url,
            style: TextStyle(color: colors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'https://music.example.com',
            ),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            key: const Key('subsonic-username-field'),
            controller: _username,
            style: TextStyle(color: colors.textPrimary),
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            key: const Key('subsonic-password-field'),
            controller: _password,
            obscureText: true,
            style: TextStyle(color: colors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Password (stored in the secure store)',
            ),
          ),
          const SizedBox(height: Spacing.md),
          Row(
            children: <Widget>[
              OutlinedButton(
                key: const Key('subsonic-test-button'),
                onPressed: _testing ? null : _testConnection,
                child: Text(_testing ? 'Testing…' : 'Test connection'),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  _testResult ?? '',
                  style: TextStyle(
                    color: _testOk ? colors.success : colors.error,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              TextButton(
                key: const Key('subsonic-remove-button'),
                onPressed: _remove,
                child: const Text('Remove'),
              ),
              FilledButton(
                key: const Key('subsonic-save-button'),
                onPressed: _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

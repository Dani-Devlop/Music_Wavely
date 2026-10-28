import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/design_system/components/components.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/features/parental/data/no_lyrics_policy.dart';
import 'package:wavely/features/parental/data/parental_providers.dart';
import 'package:wavely/features/parental/data/pin_hash.dart';

/// Parental-control management screen (PIN-gated).
///
/// Single [ListView] with sections: master switch, profiles, blocked words
/// (add / CSV import / long-press delete), artist/album/genre blocklists,
/// no-lyrics policy and the audit log (recent 50). Every write goes through
/// [ParentalDao] (+ audit) or the settings store and bumps
/// [parentalRefreshProvider] so the FutureProviders re-read.
class ParentalScreen extends ConsumerStatefulWidget {
  const ParentalScreen({super.key});

  static const String route = '/parental';

  @override
  ConsumerState<ParentalScreen> createState() => _ParentalScreenState();
}

class _ParentalScreenState extends ConsumerState<ParentalScreen> {
  bool _unlocked = false;
  final _artistCtrl = TextEditingController();
  final _albumCtrl = TextEditingController();
  final _genreCtrl = TextEditingController();
  bool _blocksHydrated = false;

  static const _severities = <String>['mild', 'moderate', 'severe'];

  @override
  void initState() {
    super.initState();
    _hydrateBlocklists();
  }

  @override
  void dispose() {
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    _genreCtrl.dispose();
    super.dispose();
  }

  Future<void> _hydrateBlocklists() async {
    final store = ref.read(settingsStoreProvider);
    final artists = await _readList(store, kParentalBlockedArtistsKey);
    final albums = await _readList(store, kParentalBlockedAlbumsKey);
    final genres = await _readList(store, kParentalBlockedGenresKey);
    if (!mounted) {
      return;
    }
    setState(() {
      _artistCtrl.text = artists.join(', ');
      _albumCtrl.text = albums.join(', ');
      _genreCtrl.text = genres.join(', ');
      _blocksHydrated = true;
    });
  }

  void _bump() => ref.read(parentalRefreshProvider.notifier).state++;

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(parentalProfilesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Parental control')),
      body: profilesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load profiles: $e')),
        data: (profiles) {
          final pinProfile = profiles
              .where((p) => p.pinHash != null && p.pinHash!.isNotEmpty)
              .firstOrNull;
          if (pinProfile != null && !_unlocked) {
            return _PinGate(
              profileName: pinProfile.name,
              pinHash: pinProfile.pinHash!,
              onUnlocked: () => setState(() => _unlocked = true),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildEnableCard(),
              _buildProfilesSection(profiles),
              _buildWordsSection(),
              _buildBlocksSection(),
              _buildNoLyricsCard(),
              _buildCensorFallbackCard(),
              _buildAuditSection(),
            ],
          );
        },
      ),
    );
  }

  // -- master switch --------------------------------------------------------

  Widget _buildEnableCard() {
    final statusAsync = ref.watch(parentalStatusProvider);
    return _Card(
      child: statusAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (e, _) => Text('Status unavailable: $e'),
        data: (status) => SwitchListTile(
          title: const Text('Parental control'),
          subtitle: const Text('Filter tracks and censor explicit lyrics'),
          value: status.enabled,
          onChanged: (value) async {
            await ref
                .read(settingsStoreProvider)
                .write(kParentalEnabledKey, value);
            await ref.read(parentalDaoProvider).audit('parental_toggled');
            _bump();
          },
        ),
      ),
    );
  }

  // -- profiles -------------------------------------------------------------

  Widget _buildProfilesSection(List<LocalProfileRow> profiles) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Profiles',
            actionLabel: 'Add',
            onAction: () => _showProfileDialog(),
          ),
          for (final profile in profiles)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(profile.name),
              subtitle: Text(
                profile.blockNoLyrics
                    ? 'Blocks tracks without lyrics'
                    : 'Allows tracks without lyrics',
              ),
            ),
          if (profiles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('No profiles yet.'),
            ),
        ],
      ),
    );
  }

  Future<void> _showProfileDialog() async {
    final nameCtrl = TextEditingController();
    var blockNoLyrics = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('profile-name-field'),
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              SwitchListTile(
                title: const Text('Block tracks without lyrics'),
                value: blockNoLyrics,
                onChanged: (v) => setDialogState(() => blockNoLyrics = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('profile-save-button'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) {
      return;
    }
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      return;
    }
    final dao = ref.read(parentalDaoProvider);
    await dao.createProfile(name: name, blockNoLyrics: blockNoLyrics);
    await dao.audit(
      'profile_created',
      details: {'name': name, 'blockNoLyrics': blockNoLyrics},
    );
    _bump();
  }

  // -- blocked words --------------------------------------------------------

  Widget _buildWordsSection() {
    final wordsAsync = ref.watch(blockedWordsProvider);
    final words = wordsAsync.valueOrNull;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Blocked words'),
          if (words != null)
            for (final word in words)
              ListTile(
                key: Key('word-tile-${word.word}'),
                title: Text(word.word),
                subtitle: Text('Severity: ${word.severity}'),
                onLongPress: () => _confirmDeleteWord(word.word),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove ${word.word}',
                  onPressed: () => _confirmDeleteWord(word.word),
                ),
              ),
          if (words == null)
            const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            )
          else if (words.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('No blocked words yet.'),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('add-word-button'),
                  onPressed: () => _showAddWordDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add word'),
                ),
                OutlinedButton.icon(
                  key: const Key('import-words-button'),
                  onPressed: () => _showImportCsvDialog(),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import CSV'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteWord(String word) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove "$word"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final dao = ref.read(parentalDaoProvider);
    await dao.removeWord(word);
    await dao.audit('word_removed', details: {'word': word});
    _bump();
  }

  Future<void> _showAddWordDialog() async {
    final wordCtrl = TextEditingController();
    var severity = 'moderate';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add blocked word'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('word-field'),
                controller: wordCtrl,
                decoration: const InputDecoration(labelText: 'Word'),
              ),
              DropdownButtonFormField<String>(
                key: const Key('severity-dropdown'),
                value: severity,
                items: [
                  for (final s in _severities)
                    DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (v) =>
                    setDialogState(() => severity = v ?? 'moderate'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('word-save-button'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) {
      return;
    }
    final word = wordCtrl.text.trim().toLowerCase();
    if (word.isEmpty) {
      return;
    }
    final dao = ref.read(parentalDaoProvider);
    await dao.addWord(word: word, severity: severity);
    await dao.audit(
      'word_added',
      details: {'word': word, 'severity': severity},
    );
    _bump();
  }

  Future<void> _showImportCsvDialog() async {
    final csvCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import words (CSV)'),
        content: TextField(
          key: const Key('csv-field'),
          controller: csvCtrl,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: "One per line:\nshit, severe\ndamn, moderate",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('csv-save-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) {
      return;
    }
    final dao = ref.read(parentalDaoProvider);
    var count = 0;
    for (final line in csvCtrl.text.split('\n')) {
      final parts = line.split(',');
      final word = parts.first.trim().toLowerCase();
      if (word.isEmpty) {
        continue;
      }
      final severity =
          parts.length > 1 ? parts[1].trim().toLowerCase() : 'moderate';
      await dao.addWord(
        word: word,
        severity: _severities.contains(severity) ? severity : 'moderate',
      );
      count++;
    }
    if (count > 0) {
      await dao.audit('words_imported', details: {'count': count});
    }
    _bump();
  }

  // -- artist / album / genre blocklists ------------------------------------

  Widget _buildBlocksSection() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Blocks'),
          if (!_blocksHydrated)
            const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  TextField(
                    key: const Key('blocked-artists-field'),
                    controller: _artistCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Blocked artists',
                      hintText: 'comma, separated, names',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('blocked-albums-field'),
                    controller: _albumCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Blocked albums',
                      hintText: 'comma, separated, titles',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('blocked-genres-field'),
                    controller: _genreCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Blocked genres',
                      hintText: 'metal, horrorcore',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: const Key('save-blocks-button'),
                      onPressed: _saveBlocks,
                      child: const Text('Save blocks'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveBlocks() async {
    final store = ref.read(settingsStoreProvider);
    await store.write(
      kParentalBlockedArtistsKey,
      _splitCsv(_artistCtrl.text),
    );
    await store.write(kParentalBlockedAlbumsKey, _splitCsv(_albumCtrl.text));
    await store.write(kParentalBlockedGenresKey, _splitCsv(_genreCtrl.text));
    await ref.read(parentalDaoProvider).audit('blocklists_updated');
    _bump();
  }

  static List<String> _splitCsv(String raw) => raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  // -- no-lyrics policy -----------------------------------------------------

  Widget _buildNoLyricsCard() {
    final filterAsync = ref.watch(trackFilterProvider);
    return _Card(
      child: filterAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (e, _) => Text('Policy unavailable: $e'),
        data: (filter) => SwitchListTile(
          title: const Text('Block tracks without lyrics'),
          subtitle: const Text('No lyrics source found → never play'),
          value: filter.blockNoLyrics,
          onChanged: (value) async {
            await ref
                .read(settingsStoreProvider)
                .write(kParentalBlockNoLyricsKey, value);
            await ref
                .read(parentalDaoProvider)
                .audit('no_lyrics_policy_changed');
            _bump();
          },
        ),
      ),
    );
  }

  // -- censor-fallback policy (BUG-9) ---------------------------------------

  Widget _buildCensorFallbackCard() {
    final policyAsync = ref.watch(noLyricsPolicyProvider);
    return _Card(
      child: policyAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (e, _) => Text('Policy unavailable: $e'),
        data: (policy) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              title: Text('Explicit fallback policy'),
              subtitle: Text(
                'What happens when a track is explicit but censoring is '
                'impossible (no synced lyrics or render failure).',
              ),
              isThreeLine: true,
              contentPadding: EdgeInsets.zero,
            ),
            RadioListTile<NoLyricsPolicy>(
              title: const Text('Block (skip the track)'),
              subtitle: const Text('Default — never plays uncensored'),
              value: NoLyricsPolicy.block,
              groupValue: policy,
              onChanged: (_) => _saveNoLyricsPolicy(NoLyricsPolicy.block),
            ),
            RadioListTile<NoLyricsPolicy>(
              title: const Text('Mute (play silently)'),
              subtitle: const Text('Track plays with the output muted'),
              value: NoLyricsPolicy.mute,
              groupValue: policy,
              onChanged: (_) => _saveNoLyricsPolicy(NoLyricsPolicy.mute),
            ),
            RadioListTile<NoLyricsPolicy>(
              title: const Text('Allow (play uncensored)'),
              subtitle: const Text('Legacy behavior — every bypass is '
                  'written to the audit log'),
              value: NoLyricsPolicy.allow,
              groupValue: policy,
              onChanged: (_) => _saveNoLyricsPolicy(NoLyricsPolicy.allow),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveNoLyricsPolicy(NoLyricsPolicy policy) async {
    await ref
        .read(settingsStoreProvider)
        .write(kParentalNoLyricsPolicyKey, policy.name);
    await ref
        .read(parentalDaoProvider)
        .audit(
          'no_lyrics_policy_changed',
          details: <String, Object?>{'policy': policy.name},
        );
    _bump();
  }

  // -- audit log ------------------------------------------------------------

  Widget _buildAuditSection() {
    final auditAsync = ref.watch(parentalAuditProvider);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Audit log'),
          auditAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Audit log unavailable: $e'),
            ),
            data: (rows) => Column(
              children: [
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nothing logged yet.'),
                  ),
                for (final row in rows)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.history, size: 20),
                    title: Text(row.event),
                    subtitle: Text(row.details),
                    trailing: Text(
                      '${row.occurredAt.hour.toString().padLeft(2, '0')}:'
                      '${row.occurredAt.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -- PIN gate -----------------------------------------------------------------

class _PinGate extends ConsumerStatefulWidget {
  const _PinGate({
    required this.profileName,
    required this.pinHash,
    required this.onUnlocked,
  });

  final String profileName;
  final String pinHash;
  final VoidCallback onUnlocked;

  @override
  ConsumerState<_PinGate> createState() => _PinGateState();
}

class _PinGateState extends ConsumerState<_PinGate>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _onKey(String digit) {
    if (_pin.length >= 4) {
      return;
    }
    setState(() => _pin += digit);
    if (_pin.length == 4) {
      _verify();
    }
  }

  Future<void> _verify() async {
    if (verifyPin(_pin, widget.pinHash)) {
      await ref.read(parentalDaoProvider).audit('pin_unlocked');
      widget.onUnlocked();
      return;
    }
    setState(() => _pin = '');
    _shake.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final dx =
            _shake.isAnimating ? 10 * (1 - _shake.value * 2) : 0.0;
        return Transform.translate(
          offset: Offset(dx, 0),
          child: child,
        );
      },
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Enter PIN for ${widget.profileName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    key: Key('pin-dot-$i'),
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length
                          ? colors.accentColors.accent
                          : colors.elevated,
                      border: Border.all(color: colors.borderGlass),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            for (final row in const <List<String?>>[
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              [null, '0', 'del'],
            ])
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final key in row)
                    if (key == null)
                      const SizedBox(width: 72, height: 56)
                    else
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: SizedBox(
                          width: 64,
                          height: 48,
                          child: key == 'del'
                              ? IconButton(
                                  key: const Key('pin-backspace'),
                                  onPressed: () =>
                                      setState(() {
                                        if (_pin.isNotEmpty) {
                                          _pin =
                                              _pin.substring(0, _pin.length - 1);
                                        }
                                      }),
                                  icon: const Icon(Icons.backspace_outlined),
                                )
                              : FilledButton.tonal(
                                  key: Key('pin-key-$key'),
                                  onPressed: () => _onKey(key),
                                  child: Text(key),
                                ),
                        ),
                      ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// -- shared card --------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderGlass),
      ),
      child: child,
    );
  }
}

// -- small helpers ------------------------------------------------------------

Future<List<String>> _readList(SettingsStore store, String key) async =>
    (await store.read<List>(key) ?? const <Object?>[]).cast<String>();

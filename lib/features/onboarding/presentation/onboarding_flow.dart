import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, TextInputFormatter;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/library/data/library_scanner_provider.dart';
import 'package:wavely/features/onboarding/data/onboarding_repository.dart';
import 'package:wavely/features/onboarding/data/onboarding_state.dart';
import 'package:wavely/features/parental/data/pin_hash.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/features/settings/domain/settings.dart';

/// Example values used to render the storage-template preview (P6).
const String _previewArtist = 'Nova Reign';
const String _previewAlbum = 'Midnight Static';
const String _previewTitle = 'Neon Skyline';

/// Test-visible widget keys (one per interactive element the walkthrough
/// suite needs to reach without text ambiguity).
const Key kOnboardingLivePreviewKey = ValueKey<String>(
  'onboarding_live_preview',
);
const Key kOnboardingRegionFieldKey = ValueKey<String>(
  'onboarding_region_field',
);
const Key kOnboardingParentalSwitchKey = ValueKey<String>(
  'onboarding_parental_switch',
);
const Key kOnboardingPinFieldKey = ValueKey<String>('onboarding_pin_field');
const Key kOnboardingSeedWordsFieldKey = ValueKey<String>(
  'onboarding_seed_words_field',
);
const Key kOnboardingAddFolderButtonKey = ValueKey<String>(
  'onboarding_add_folder_button',
);

/// Onboarding wizard (Task B9) — 10 pages driven by a [PageView].
///
/// Nothing is persisted until the final `Finish` button: the draft lives in
/// memory ([OnboardingDraft]), then Finish flushes appearance/scan/language
/// fields through the settings notifier and onboarding-only fields through
/// [OnboardingRepository], writes the completion flag and navigates to
/// `/library`. Backing out at any page (including Done) persists nothing.
///
/// The region page never blocks the UI: the ipapi probe is fire-and-forget
/// with a 2s timeout and the locale-derived fallback is displayed
/// immediately, before (or without) any network answer.
class OnboardingFlow extends ConsumerStatefulWidget {
  /// Creates the wizard; [httpClient] is injectable so tests never touch
  /// the network (defaults to a fresh [http.Client]).
  const OnboardingFlow({super.key, this.httpClient});

  /// Route path registered by the app router.
  static const String route = '/onboarding';

  /// Async completion probe for the orchestrator's router redirect.
  ///
  /// The redirect itself uses the synchronous
  /// `OnboardingRepository(prefs).isCompleted()` — this helper mirrors the
  /// owner spec and is safe for async bootstrap code.
  static Future<bool> isCompleted(SharedPreferences prefs) async =>
      OnboardingRepository(prefs).isCompleted();

  /// Optional HTTP client override (tests inject a failing fake).
  final http.Client? httpClient;

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  static const int _pageCount = 10;
  static const Duration _pageTransition =
      Duration(milliseconds: AppConstants.fastAnimationMs);
  static const String _regionEndpoint = 'https://ipapi.co/json/';

  final PageController _pageController = PageController();
  final OnboardingDraft _draft = OnboardingDraft();
  final TextEditingController _templateController = TextEditingController();

  late final TextEditingController _regionController;
  late http.Client _client;
  late String _localeFallback;
  String _timezone = '';
  String _regionStatus = 'Checking region…';
  bool _ownsClient = false;
  bool _regionEdited = false;
  bool _regionProbeStarted = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    final provided = widget.httpClient;
    if (provided != null) {
      _client = provided;
    } else {
      _ownsClient = true;
      _client = http.Client();
    }
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    _localeFallback = locale.countryCode ?? 'US';
    _timezone = DateTime.now().timeZoneName;
    _regionController = TextEditingController(text: _localeFallback);
    _templateController.text = _draft.storageTemplate;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _regionController.dispose();
    _templateController.dispose();
    if (_ownsClient) {
      _client.close();
    }
    super.dispose();
  }

  // -- navigation -------------------------------------------------------

  void _goNext() {
    if (_page >= _pageCount - 1) {
      unawaited(_finish());
      return;
    }
    unawaited(
      _pageController.animateToPage(
        _page + 1,
        duration: _pageTransition,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _goBack() {
    if (_page == 0) {
      return;
    }
    unawaited(
      _pageController.animateToPage(
        _page - 1,
        duration: _pageTransition,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _onPageChanged(int index) {
    setState(() => _page = index);
    if (index == 2) {
      _startRegionDetection();
    }
    if (index == 7) {
      _draft.aiKeyHintShown = true;
    }
  }

  // -- region detection (P3) -----------------------------------------

  /// Fire-and-forget probe: locale/timezone fallback is already on screen
  /// before this runs, and every failure keeps that fallback in place.
  void _startRegionDetection() {
    if (_regionProbeStarted) {
      return;
    }
    _regionProbeStarted = true;
    // The displayed default IS the draft value until the user edits it —
    // so a skipped/failed probe still persists the locale fallback.
    _draft.region ??= _localeFallback;
    unawaited(_detectRegion());
  }

  Future<void> _detectRegion() async {
    String? detected;
    try {
      final response = await _client
          .get(Uri.parse(_regionEndpoint))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final code = decoded['country_code'];
          if (code is String && code.length == 2) {
            detected = code;
          }
        }
      }
    } on Object catch (_) {
      // Timeout/network/decode failure — the locale fallback stays.
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _timezone = DateTime.now().timeZoneName;
      if (detected == null) {
        _regionStatus = 'Network detection failed — using locale fallback';
        return;
      }
      _regionStatus = 'Detected via network: $detected';
      if (!_regionEdited) {
        _draft.region = detected;
        _regionController.text = detected;
      }
    });
  }

  // -- actions ---------------------------------------------------------

  Future<void> _pickFolders() async {
    final picked = await ref.read(libraryScannerProvider).pickFolders();
    if (!mounted) {
      return;
    }
    setState(() {
      final folders = List<String>.of(_draft.scanFolders);
      for (final folder in picked) {
        if (!folders.contains(folder)) {
          folders.add(folder);
        }
      }
      _draft.scanFolders = folders;
    });
  }

  void _removeFolder(String folder) {
    setState(() {
      _draft.scanFolders = _draft.scanFolders
          .where((f) => f != folder)
          .toList(growable: false);
    });
  }

  void _reorderLanguages(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final moved = _draft.languagePriorities.removeAt(oldIndex);
      _draft.languagePriorities.insert(newIndex, moved);
    });
  }

  /// Flushes the draft: settings notifier setters, onboarding-only prefs,
  /// the parental profile + seed words, then the completion flag, then
  /// navigates to `/library`.
  Future<void> _finish() async {
    // Stage 3 audit (BUG-13): re-entrancy guard — a Finish double-tap used
    // to run the flush twice and create duplicate 'family' parental
    // profiles. The flag resets on failure so the user can retry.
    if (_finishing) {
      return;
    }
    _finishing = true;
    try {
      await _finishOnce();
    } finally {
      _finishing = false;
    }
  }

  bool _finishing = false;

  Future<void> _finishOnce() async {
    final draft = _draft;
    final notifier = ref.read(settingsProvider.notifier);
    notifier
      ..setThemeMode(draft.themeMode)
      ..setAccent(draft.accent)
      ..setStorageTemplate(draft.storageTemplate)
      ..setNeverPlayLanguages(draft.neverPlayLanguages);
    for (final folder in draft.scanFolders) {
      notifier.addScanFolder(folder);
    }

    final repo = OnboardingRepository(ref.read(sharedPrefsProvider));
    await repo.saveDownloadQuality(draft.downloadQuality);
    await repo.saveLanguagePriorities(draft.languagePriorities);
    await repo.saveRegion(draft.region);
    await repo.saveAiConsent(draft.aiConsent);

    if (draft.parentalEnabled) {
      final dao = ref.read(databaseProvider).parentalDao;
      final pin = draft.parentalPin;
      final pinHash = (pin == null || pin.isEmpty)
          ? null
          : hashPin(pin);
      await dao.createProfile(name: 'family', pinHash: pinHash);
      for (final word in draft.blockedSeedWords) {
        await dao.addWord(word: word);
      }
    }

    await repo.markCompleted();
    if (!mounted) {
      return;
    }
    // maybeOf keeps standalone pumps (docs, previews) crash-free.
    GoRouter.maybeOf(context)?.go('/library');
  }

  // -- chrome ---------------------------------------------------------------

  Widget _header(WavelySemanticColors colors) => Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.md,
          Spacing.lg,
          Spacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Text(
              'Set up Wavely',
              style: WavelyTypography.title20(color: colors.textPrimary),
            ),
            const Spacer(),
            Text(
              '${_page + 1} / $_pageCount',
              key: ValueKey<String>('onboarding_progress_${_page + 1}'),
              style: WavelyTypography.body14(color: colors.textSecondary),
            ),
          ],
        ),
      );

  Widget _navBar(WavelySemanticColors colors) => Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Row(
          children: <Widget>[
            SizedBox(
              height: AppConstants.touchTargetMin,
              child: TextButton(
                onPressed: _page == 0 ? null : _goBack,
                child: const Text('Back'),
              ),
            ),
            const Spacer(),
            SizedBox(
              height: AppConstants.touchTargetMin,
              child: FilledButton(
                onPressed: _goNext,
                child: Text(_page == _pageCount - 1 ? 'Finish' : 'Next'),
              ),
            ),
          ],
        ),
      );

  // -- pages ---------------------------------------------------------------

  Widget _buildPage(int index) => switch (index) {
        0 => _welcomePage(),
        1 => _themePage(),
        2 => _regionPage(),
        3 => _languagePage(),
        4 => _qualityPage(),
        5 => _templatePage(),
        6 => _parentalPage(),
        7 => _aiPage(),
        8 => _foldersPage(),
        _ => _donePage(),
      };

  Widget _pageScaffold({
    required String title,
    required List<Widget> children,
  }) =>
      SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: WavelyTypography.title18()),
            const SizedBox(height: Spacing.md),
            ...children,
          ],
        ),
      );

  Widget _welcomePage() => _pageScaffold(
        title: 'Welcome to Wavely',
        children: <Widget>[
          const Center(
            child: Icon(Icons.graphic_eq, size: 96),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'A glassy, privacy-first music player for legal sources only.',
            style: WavelyTypography.body14(),
          ),
          const SizedBox(height: Spacing.lg),
          Card(
            child: ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Privacy first'),
              subtitle: const Text(
                'Crash reports only — no analytics, no tracking. Your API '
                'keys stay on this device.',
              ),
            ),
          ),
        ],
      );

  Widget _themePage() => _pageScaffold(
        title: 'Appearance',
        children: <Widget>[
          const Text('Theme mode'),
          const SizedBox(height: Spacing.sm),
          SizedBox(
            width: double.infinity,
            height: AppConstants.touchTargetMin,
            child: SegmentedButton<ThemeMode>(
              segments: const <ButtonSegment<ThemeMode>>[
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.system,
                  label: Text('System'),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.light,
                  label: Text('Light'),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                ),
              ],
              selected: <ThemeMode>{_draft.themeMode},
              onSelectionChanged: (Set<ThemeMode> selection) => setState(
                () => _draft.themeMode = selection.first,
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          const Text('Accent'),
          const SizedBox(height: Spacing.sm),
          Row(
            children: <Widget>[
              for (final accent in AccentColor.values)
                Padding(
                  padding: const EdgeInsets.only(right: Spacing.md),
                  child: _accentTile(accent),
                ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          _livePreview(),
        ],
      );

  Widget _accentTile(AccentColor accent) {
    final selected = _draft.accent == accent;
    final swatch = accent.toWavelyAccent.colors.accent;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      onTap: () => setState(() => _draft.accent = accent),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: swatch.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(
            color: selected ? swatch : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.music_note, color: swatch),
            Text(accent.name),
          ],
        ),
      ),
    );
  }

  /// Rebuilds immediately on every theme/accent change — it renders the
  /// real [WavelyThemes] pair for the pending selection (system resolves
  /// against the platform brightness).
  Widget _livePreview() {
    final Brightness brightness = switch (_draft.themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    final accent = _draft.accent.toWavelyAccent;
    final theme = brightness == Brightness.dark
        ? WavelyThemes.dark(accent)
        : WavelyThemes.light(accent);
    return Theme(
      key: kOnboardingLivePreviewKey,
      data: theme,
      child: Builder(
        builder: (BuildContext context) {
          final colors = context.wavelyColors;
          return Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: colors.borderGlass),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _previewTitle,
                        style: WavelyTypography.body14Medium(
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        '$_previewArtist · $_previewAlbum',
                        style: WavelyTypography.caption12(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _regionPage() => _pageScaffold(
        title: 'Region',
        children: <Widget>[
          Text(
            'Locale fallback: $_localeFallback · Timezone: $_timezone',
            style: WavelyTypography.caption12(
              color: context.wavelyColors.textSecondary,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            key: kOnboardingRegionFieldKey,
            controller: _regionController,
            maxLength: 2,
            onChanged: (String value) {
              _regionEdited = true;
              _draft.region = value;
            },
            decoration: InputDecoration(
              labelText: 'Country code',
              helperText: _regionStatus,
            ),
          ),
        ],
      );

  Widget _languagePage() => _pageScaffold(
        title: 'Languages',
        children: <Widget>[
          const Text('Priority order (drag to reorder)'),
          SizedBox(
            height: 280,
            child: ReorderableListView(
              onReorder: _reorderLanguages,
              buildDefaultDragHandles: true,
              children: <Widget>[
                for (var i = 0; i < _draft.languagePriorities.length; i++)
                  Container(
                    key: ValueKey<String>(
                      'onboarding-lang-${_draft.languagePriorities[i]}',
                    ),
                    child: ListTile(
                      leading: Text('${i + 1}'),
                      title: Text(_draft.languagePriorities[i]),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),
          const Text('Never play'),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            children: <Widget>[
              for (final language in kOnboardingLanguages)
                FilterChip(
                  label: Text(language),
                  selected: _draft.neverPlayLanguages.contains(language),
                  onSelected: (bool selected) => setState(() {
                    final languages = List<String>.of(
                      _draft.neverPlayLanguages,
                    );
                    if (selected) {
                      languages.add(language);
                    } else {
                      languages.remove(language);
                    }
                    _draft.neverPlayLanguages = languages;
                  }),
                ),
            ],
          ),
        ],
      );

  Widget _qualityPage() => _pageScaffold(
        title: 'Download quality',
        children: <Widget>[
          for (final quality in OnboardingDownloadQuality.values)
            RadioListTile<OnboardingDownloadQuality>(
              value: quality,
              groupValue: _draft.downloadQuality,
              onChanged: (OnboardingDownloadQuality? value) => setState(
                () => _draft.downloadQuality = value ?? quality,
              ),
              title: Text(switch (quality) {
                OnboardingDownloadQuality.q320 => '320 kbps',
                OnboardingDownloadQuality.flac => 'FLAC (lossless)',
                OnboardingDownloadQuality.ask => 'Ask every time',
              }),
            ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Applies when downloads arrive (Stage 2.1).',
            style: WavelyTypography.caption12(
              color: context.wavelyColors.textSecondary,
            ),
          ),
        ],
      );

  Widget _templatePage() => _pageScaffold(
        title: 'Storage layout',
        children: <Widget>[
          TextField(
            controller: _templateController,
            onChanged: (String value) =>
                setState(() => _draft.storageTemplate = value),
            decoration: const InputDecoration(
              labelText: 'Template',
              helperText: 'Tokens: {artist} {album} {title}',
            ),
          ),
          const SizedBox(height: Spacing.md),
          Text('Preview', style: WavelyTypography.title18()),
          const SizedBox(height: Spacing.sm),
          Text(_renderTemplate(_draft.storageTemplate)),
        ],
      );

  String _renderTemplate(String template) => template
      .replaceAll('{artist}', _previewArtist)
      .replaceAll('{album}', _previewAlbum)
      .replaceAll('{title}', _previewTitle);

  Widget _parentalPage() => _pageScaffold(
        title: 'Parental mode',
        children: <Widget>[
          SwitchListTile(
            key: kOnboardingParentalSwitchKey,
            value: _draft.parentalEnabled,
            onChanged: (bool enabled) =>
                setState(() => _draft.parentalEnabled = enabled),
            title: const Text('Enable parental mode'),
            subtitle: const Text('Pin-protected, starter block list'),
          ),
          if (_draft.parentalEnabled) ...<Widget>[
            TextField(
              key: kOnboardingPinFieldKey,
              obscureText: true,
              maxLength: 4,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: (String value) => _draft.parentalPin = value,
              decoration: const InputDecoration(labelText: '4-digit PIN'),
            ),
            TextField(
              key: kOnboardingSeedWordsFieldKey,
              onChanged: (String value) => _draft.blockedSeedWords = value
                  .split(',')
                  .map((String word) => word.trim())
                  .where((String word) => word.isNotEmpty)
                  .toList(growable: false),
              decoration: const InputDecoration(
                labelText: 'Starter word list',
                helperText: 'Comma separated',
              ),
            ),
          ],
        ],
      );

  Widget _aiPage() => _pageScaffold(
        title: 'AI features',
        children: <Widget>[
          SwitchListTile(
            value: _draft.aiConsent,
            onChanged: (bool consent) =>
                setState(() => _draft.aiConsent = consent),
            title: const Text('Enable AI features'),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Bring your own key: set GEMINI_API_KEY or OPENAI_API_KEY in '
            '.env (see .env.example).',
            style: WavelyTypography.caption12(
              color: context.wavelyColors.textSecondary,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          const Text('You can skip this — enable later in Settings.'),
        ],
      );

  Widget _foldersPage() => _pageScaffold(
        title: 'Music folders',
        children: <Widget>[
          SizedBox(
            height: AppConstants.touchTargetMin,
            child: FilledButton.icon(
              key: kOnboardingAddFolderButtonKey,
              onPressed: () => unawaited(_pickFolders()),
              icon: const Icon(Icons.folder_open),
              label: const Text('Add music folder'),
            ),
          ),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.sm,
            children: <Widget>[
              for (final folder in _draft.scanFolders)
                InputChip(
                  label: Text(folder),
                  onPressed: () => _removeFolder(folder),
                  onDeleted: () => _removeFolder(folder),
                ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Scan starts after setup.',
            style: WavelyTypography.caption12(
              color: context.wavelyColors.textSecondary,
            ),
          ),
        ],
      );

  Widget _donePage() => _pageScaffold(
        title: 'Done',
        children: <Widget>[
          Text(
            'Everything below is applied when you press Finish — backing '
            'out keeps your previous settings untouched.',
            style: WavelyTypography.caption12(
              color: context.wavelyColors.textSecondary,
            ),
          ),
          const SizedBox(height: Spacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _summaryLine(
                    'Theme: ${_draft.themeMode.name} · '
                    'Accent: ${_draft.accent.name}',
                  ),
                  _summaryLine('Region: ${_draft.region ?? '-'}'),
                  _summaryLine(
                    'Languages: ${_draft.languagePriorities.join(', ')}',
                  ),
                  _summaryLine(
                    'Never play: ${_neverPlaySummary()}',
                  ),
                  _summaryLine(
                    'Download quality: ${_draft.downloadQuality.name}',
                  ),
                  _summaryLine(
                    'Storage: ${_renderTemplate(_draft.storageTemplate)}',
                  ),
                  _summaryLine(
                    'Parental: ${_draft.parentalEnabled ? 'on' : 'off'} · '
                    'AI: ${_draft.aiConsent ? 'yes' : 'no'}',
                  ),
                  _summaryLine('Folders: ${_draft.scanFolders.length}'),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _summaryLine(String text) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.xs),
        child: Text(text, style: WavelyTypography.body14()),
      );

  String _neverPlaySummary() {
    final languages = _draft.neverPlayLanguages;
    return languages.isEmpty ? 'none' : languages.join(', ');
  }

  // -- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _header(colors),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                children: <Widget>[
                  for (var i = 0; i < _pageCount; i++) _buildPage(i),
                ],
              ),
            ),
            _navBar(colors),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Common regions offered as one-tap chips on the region page (P3). The
/// custom field below the chips still accepts any ISO-3166 alpha-2 code.
const Map<String, String> _kRegionChips = <String, String>{
  'US': 'United States',
  'GB': 'United Kingdom',
  'DE': 'Germany',
  'FR': 'France',
  'ES': 'Spain',
  'IT': 'Italy',
  'IR': 'Iran',
  'TR': 'Türkiye',
  'IN': 'India',
  'JP': 'Japan',
  'KR': 'South Korea',
  'BR': 'Brazil',
};

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

/// Onboarding wizard (Task B9, 2026 visual overhaul) — 10 pages driven by a
/// full-screen [PageView].
///
/// The experience is deliberately visual instead of form-like: a gradient
/// backdrop with a glass hero header, per-page entrance animations, large
/// vector-icon selectors (theme swatch cards, region/language chips,
/// download-quality cards with CD/waveform artwork), a visual
/// folder-structure preview and a fixed premium glass bottom bar with
/// Back / progress dots / Next.
///
/// Nothing is persisted until the final `Finish` button: the draft lives in
/// memory ([OnboardingDraft]), then Finish flushes appearance/scan/language
/// fields through the settings notifier and onboarding-only fields through
/// [OnboardingRepository], writes the completion flag and navigates to
/// `/home`. Backing out at any page (including Done) persists nothing.
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

  void _selectRegion(String code) {
    setState(() {
      _regionEdited = true;
      _draft.region = code;
      _regionController.text = code;
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
  /// navigates to `/home`.
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
    GoRouter.maybeOf(context)?.go('/home');
  }

  // -- chrome ---------------------------------------------------------------

  /// Gradient backdrop + soft accent glow blob behind the content.
  Widget _backdrop(WavelySemanticColors colors) {
    final accent = colors.accentColors;
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: <Color>[
                  colors.bgBase,
                  accent.gradientStart.withValues(
                    alpha: colors.isDark ? 0.16 : 0.08,
                  ),
                  colors.bgBase,
                ],
                stops: const <double>[0, 0.45, 1],
              ),
            ),
          ),
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    accent.accent.withValues(alpha: colors.isDark ? 0.22 : 0.12),
                    accent.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(WavelySemanticColors colors) => Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.md,
          Spacing.lg,
          Spacing.sm,
        ),
        child: Row(
          children: <Widget>[
            _logoBadge(colors, size: 40, iconSize: 22),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                'Set up Wavely',
                style: WavelyTypography.title20(color: colors.textPrimary),
              ),
            ),
            Text(
              '${_page + 1} / $_pageCount',
              key: ValueKey<String>('onboarding_progress_${_page + 1}'),
              style: WavelyTypography.caption12(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      );

  /// The Wavely mark: a gradient circle with a waveform glyph and a soft
  /// accent glow.
  Widget _logoBadge(
    WavelySemanticColors colors, {
    required double size,
    required double iconSize,
  }) {
    final accent = colors.accentColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[accent.hover, accent.gradientStart],
        ),
        border: Border.all(color: colors.borderGlass),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.accent.withValues(alpha: 0.4),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(
        Icons.graphic_eq_rounded,
        size: iconSize,
        color: Colors.white,
      ),
    );
  }

  Widget _navBar(WavelySemanticColors colors) => Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.xs,
          Spacing.lg,
          Spacing.lg,
        ),
        child: GlassCard(
          blurSigma: 24,
          borderRadius: AppRadii.bXl,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                height: AppConstants.touchTargetMin,
                child: TextButton.icon(
                  onPressed: _page == 0 ? null : _goBack,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('Back'),
                ),
              ),
              // v1.0.2: FittedBox keeps the page dots on narrow (Android,
              // < 800 px) viewports — the row used to overflow on 390 px.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      for (var i = 0; i < _pageCount; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.symmetric(
                            horizontal: Spacing.xs + 1,
                          ),
                          width: i == _page ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            borderRadius: AppRadii.bPill,
                            color: i == _page
                                ? colors.accentColors.accent
                                : colors.textTertiary
                                    .withValues(alpha: 0.45),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: AppConstants.touchTargetMin,
                child: FilledButton.icon(
                  onPressed: _goNext,
                  icon: Icon(
                    _page == _pageCount - 1
                        ? Icons.check_rounded
                        : Icons.chevron_right_rounded,
                  ),
                  label: Text(_page == _pageCount - 1 ? 'Finish' : 'Next'),
                ),
              ),
            ],
          ),
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

  /// Per-page entrance: fade + rise, played when the page is first built.
  Widget _pageScaffold({
    required int index,
    required String title,
    required List<Widget> children, String? subtitle,
  }) =>
      TweenAnimationBuilder<double>(
        key: ValueKey<String>('onboarding-entrance-$index'),
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 16),
            child: child,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.md,
            Spacing.lg,
            Spacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: WavelyTypography.display24(
                  color: context.wavelyColors.textPrimary,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: Spacing.xs),
                Text(
                  subtitle,
                  style: WavelyTypography.body14(
                    color: context.wavelyColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: Spacing.lg),
              ...children,
            ],
          ),
        ),
      );

  Widget _welcomePage() => _pageScaffold(
        index: 0,
        title: 'Welcome to Wavely',
        subtitle: 'A glassy, privacy-first music player for legal sources '
            'only — ten taps and you are listening.',
        children: <Widget>[
          const SizedBox(height: Spacing.lg),
          Center(
            child: _logoBadge(
              context.wavelyColors,
              size: 128,
              iconSize: 64,
            ),
          ),
          const SizedBox(height: Spacing.xl),
          _featureRow(
            context.wavelyColors,
            icon: Icons.library_music_rounded,
            title: 'Your local library',
            subtitle: 'FLAC, MP3 and more — scanned on-device, bit-perfect.',
          ),
          _featureRow(
            context.wavelyColors,
            icon: Icons.explore_rounded,
            title: 'Legal online sources',
            subtitle: 'Jamendo, FMA, Archive.org and your own Subsonic '
                'server — clearly separated from local.',
          ),
          _featureRow(
            context.wavelyColors,
            icon: Icons.shield_outlined,
            title: 'Privacy first',
            subtitle: 'Crash reports only — no analytics, no tracking. Your '
                'API keys stay on this device.',
          ),
        ],
      );

  Widget _featureRow(
    WavelySemanticColors colors, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final accent = colors.accentColors;
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.bLg,
        border: Border.all(color: colors.borderGlass),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: AppRadii.bMd,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[accent.accent, accent.gradientStart],
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: WavelyTypography.body14Medium(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
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
  }

  Widget _themePage() => _pageScaffold(
        index: 1,
        title: 'Appearance',
        subtitle: 'Pick how Wavely feels — every change previews live.',
        children: <Widget>[
          Row(
            children: <Widget>[
              for (final mode in ThemeMode.values) ...<Widget>[
                if (mode != ThemeMode.values.first)
                  const SizedBox(width: Spacing.sm),
                Expanded(child: _themeModeCard(mode)),
              ],
            ],
          ),
          const SizedBox(height: Spacing.xl),
          Text(
            'Accent',
            style: WavelyTypography.title18(
              color: context.wavelyColors.textPrimary,
            ),
          ),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.md,
            runSpacing: Spacing.md,
            children: <Widget>[
              for (final accent in AccentColor.values) _accentSwatch(accent),
            ],
          ),
          const SizedBox(height: Spacing.xl),
          _livePreview(),
        ],
      );

  /// Visual theme-mode card (replaces the old SegmentedButton).
  Widget _themeModeCard(ThemeMode mode) {
    final colors = context.wavelyColors;
    final selected = _draft.themeMode == mode;
    final accent = colors.accentColors.accent;
    final (icon, label, caption) = switch (mode) {
      ThemeMode.system => (
          Icons.brightness_auto_rounded,
          'System',
          'Follow the OS',
        ),
      ThemeMode.light => (Icons.light_mode_rounded, 'Light', 'Bright & airy'),
      ThemeMode.dark => (Icons.dark_mode_rounded, 'Dark', 'Deep & glassy'),
    };
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: AppRadii.bLg,
        onTap: () => setState(() => _draft.themeMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(
            vertical: Spacing.md,
            horizontal: Spacing.xs,
          ),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : colors.surface,
            borderRadius: AppRadii.bLg,
            border: Border.all(
              color: selected ? accent : colors.borderGlass,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: <Widget>[
              Icon(
                icon,
                size: 28,
                color: selected ? accent : colors.textSecondary,
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                label,
                style: WavelyTypography.body14Medium(
                  color: selected ? accent : colors.textPrimary,
                ),
              ),
              Text(
                caption,
                style: WavelyTypography.micro10(color: colors.textTertiary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accentSwatch(AccentColor accent) {
    final selected = _draft.accent == accent;
    final swatch = accent.toWavelyAccent.colors.accent;
    return Semantics(
      button: true,
      selected: selected,
      label: accent.name,
      child: InkWell(
        borderRadius: AppRadii.bPill,
        onTap: () => setState(() => _draft.accent = accent),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                accent.toWavelyAccent.colors.hover,
                accent.toWavelyAccent.colors.gradientStart,
              ],
            ),
            border: Border.all(
              color: selected ? Colors.white : Colors.transparent,
              width: 3,
            ),
            boxShadow: selected
                ? <BoxShadow>[
                    BoxShadow(
                      color: swatch.withValues(alpha: 0.55),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: selected
              ? const Icon(Icons.check_rounded, color: Colors.white)
              : null,
        ),
      ),
    );
  }

  /// Rebuilds immediately on every theme/accent change — it renders the
  /// real [WavelyThemes] pair for the pending selection (system resolves
  /// against the platform brightness).
  Widget _livePreview() {
    final brightness = switch (_draft.themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    final accent = _draft.accent.toWavelyAccent;
    final theme = brightness == Brightness.dark
        ? WavelyThemes.dark(accent.colors)
        : WavelyThemes.light(accent.colors);
    return Theme(
      key: kOnboardingLivePreviewKey,
      data: theme,
      child: Builder(
        builder: (context) {
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
        index: 2,
        title: 'Region',
        subtitle: 'Used for legal-source availability and metadata.',
        children: <Widget>[
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: <Widget>[
              for (final entry in _kRegionChips.entries)
                _regionChip(entry.key, entry.value),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          TextField(
            key: kOnboardingRegionFieldKey,
            controller: _regionController,
            maxLength: 2,
            onChanged: (value) {
              _regionEdited = true;
              _draft.region = value;
            },
            decoration: InputDecoration(
              labelText: 'Country code',
              helperText: '$_regionStatus · Timezone: $_timezone',
            ),
          ),
        ],
      );

  Widget _regionChip(String code, String name) {
    final colors = context.wavelyColors;
    final selected = _draft.region == code;
    final accent = colors.accentColors.accent;
    return FilterChip(
      selected: selected,
      onSelected: (_) => _selectRegion(code),
      avatar: selected
          ? Icon(Icons.check_circle_rounded, size: 18, color: accent)
          : Text(
              code,
              style: WavelyTypography.micro10(color: colors.textSecondary),
            ),
      label: Text(
        name,
        style: WavelyTypography.body14Medium(
          color: selected ? accent : colors.textPrimary,
        ),
      ),
      backgroundColor: colors.surface,
      selectedColor: accent.withValues(alpha: 0.16),
      checkmarkColor: accent,
      side: BorderSide(color: selected ? accent : colors.borderGlass),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.bPill),
      showCheckmark: false,
    );
  }

  Widget _languagePage() => _pageScaffold(
        index: 3,
        title: 'Languages',
        subtitle: 'Priority order first — then anything Wavely must never '
            'autoplay.',
        children: <Widget>[
          Text(
            'Priority order (drag to reorder)',
            style: WavelyTypography.title18(
              color: context.wavelyColors.textPrimary,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          SizedBox(
            height: 220,
            child: ReorderableListView(
              onReorder: _reorderLanguages,
              children: <Widget>[
                for (var i = 0; i < _draft.languagePriorities.length; i++)
                  Container(
                    key: ValueKey<String>(
                      'onboarding-lang-${_draft.languagePriorities[i]}',
                    ),
                    margin: const EdgeInsets.only(bottom: Spacing.sm),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: Spacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: context.wavelyColors.surface,
                      borderRadius: AppRadii.bMd,
                      border: Border.all(
                        color: context.wavelyColors.borderGlass,
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Text(
                          '${i + 1}',
                          style: WavelyTypography.body14Medium(
                            color: context.wavelyColors.accentColors.accent,
                          ),
                        ),
                        const SizedBox(width: Spacing.md),
                        Text(
                          _draft.languagePriorities[i],
                          style: WavelyTypography.body14(
                            color: context.wavelyColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Never play',
            style: WavelyTypography.title18(
              color: context.wavelyColors.textPrimary,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: <Widget>[
              for (final language in kOnboardingLanguages)
                _neverPlayChip(language),
            ],
          ),
        ],
      );

  Widget _neverPlayChip(String language) {
    final colors = context.wavelyColors;
    final selected = _draft.neverPlayLanguages.contains(language);
    final accent = colors.accentColors.accent;
    return FilterChip(
      label: Text(language),
      selected: selected,
      onSelected: (selected) => setState(() {
        final languages = List<String>.of(_draft.neverPlayLanguages);
        if (selected) {
          languages.add(language);
        } else {
          languages.remove(language);
        }
        _draft.neverPlayLanguages = languages;
      }),
      backgroundColor: colors.surface,
      selectedColor: accent.withValues(alpha: 0.16),
      checkmarkColor: accent,
      side: BorderSide(color: selected ? accent : colors.borderGlass),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.bPill),
    );
  }

  Widget _qualityPage() => _pageScaffold(
        index: 4,
        title: 'Download quality',
        subtitle: 'Applies when downloads arrive (Stage 2.1).',
        children: <Widget>[
          for (final quality in OnboardingDownloadQuality.values) ...<Widget>[
            _qualityCard(quality),
            const SizedBox(height: Spacing.sm),
          ],
        ],
      );

  /// Large visual quality card — CD artwork for FLAC, a waveform for
  /// 320 kbps, a question bubble for "ask every time".
  Widget _qualityCard(OnboardingDownloadQuality quality) {
    final colors = context.wavelyColors;
    final selected = _draft.downloadQuality == quality;
    final accent = colors.accentColors;
    final (icon, label, caption) = switch (quality) {
      OnboardingDownloadQuality.q320 => (
          Icons.graphic_eq_rounded,
          '320 kbps',
          'Great quality, smaller files',
        ),
      OnboardingDownloadQuality.flac => (
          Icons.album_rounded,
          'FLAC — lossless',
          'Up to 24-bit / 192 kHz, bit-perfect',
        ),
      OnboardingDownloadQuality.ask => (
          Icons.help_outline_rounded,
          'Ask every time',
          'Choose per download',
        ),
    };
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: AppRadii.bLg,
        onTap: () =>
            setState(() => _draft.downloadQuality = quality),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: selected ? accent.accent.withValues(alpha: 0.14) : colors.surface,
            borderRadius: AppRadii.bLg,
            border: Border.all(
              color: selected ? accent.accent : colors.borderGlass,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: AppRadii.bMd,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[accent.accent, accent.gradientStart],
                  ),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: WavelyTypography.body14Medium(
                        color: selected
                            ? accent.accent
                            : colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      caption,
                      style: WavelyTypography.caption12(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? accent.accent : Colors.transparent,
                  border: Border.all(
                    color: selected ? accent.accent : colors.textTertiary,
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check_rounded,
                        size: 16, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _templatePage() => _pageScaffold(
        index: 5,
        title: 'Storage layout',
        subtitle: 'How downloads are organised on disk.',
        children: <Widget>[
          TextField(
            controller: _templateController,
            onChanged: (value) =>
                setState(() => _draft.storageTemplate = value),
            decoration: const InputDecoration(
              labelText: 'Template',
              helperText: 'Tokens: {artist} {album} {title}',
            ),
          ),
          const SizedBox(height: Spacing.lg),
          _templateTreeCard(),
        ],
      );

  /// Visual folder-structure preview: Music/ → artist/ → album/ → title.mp3,
  /// rendered from the live template.
  Widget _templateTreeCard() {
    final colors = context.wavelyColors;
    final accent = colors.accentColors.accent;
    final segments = _draft.storageTemplate
        .split('/')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final rows = <Widget>[
      Row(
        children: <Widget>[
          Icon(Icons.folder_rounded, size: 20, color: accent),
          const SizedBox(width: Spacing.sm),
          Text(
            'Music/',
            style: WavelyTypography.body14Medium(color: colors.textPrimary),
          ),
        ],
      ),
    ];
    for (var i = 0; i < segments.length; i++) {
      final isFile = i == segments.length - 1;
      final rendered = _renderTemplate(segments[i]);
      rows.add(
        Padding(
          padding: EdgeInsetsDirectional.only(start: 20.0 * (i + 1)),
          child: Row(
            children: <Widget>[
              Icon(
                isFile ? Icons.music_note_rounded : Icons.folder_rounded,
                size: 20,
                color: isFile ? colors.textSecondary : accent,
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                isFile ? '$rendered.mp3' : '$rendered/',
                style: WavelyTypography.body14(
                  color: isFile ? colors.textSecondary : colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.bLg,
        border: Border.all(color: colors.borderGlass),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Preview',
            style: WavelyTypography.title18(color: colors.textPrimary),
          ),
          const SizedBox(height: Spacing.md),
          for (final row in rows) ...<Widget>[
            row,
            const SizedBox(height: Spacing.sm),
          ],
        ],
      ),
    );
  }

  String _renderTemplate(String template) => template
      .replaceAll('{artist}', _previewArtist)
      .replaceAll('{album}', _previewAlbum)
      .replaceAll('{title}', _previewTitle);

  Widget _parentalPage() => _pageScaffold(
        index: 6,
        title: 'Parental mode',
        subtitle: 'Pin-protected, starter block list — configurable any '
            'time in Settings.',
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              color: context.wavelyColors.surface,
              borderRadius: AppRadii.bLg,
              border: Border.all(color: context.wavelyColors.borderGlass),
            ),
            child: SwitchListTile(
              key: kOnboardingParentalSwitchKey,
              value: _draft.parentalEnabled,
              onChanged: (enabled) =>
                  setState(() => _draft.parentalEnabled = enabled),
              secondary: Icon(
                Icons.family_restroom_rounded,
                color: context.wavelyColors.accentColors.accent,
              ),
              title: const Text('Enable parental mode'),
              subtitle: const Text('Auto-censor swearing · PIN lock'),
            ),
          ),
          if (_draft.parentalEnabled) ...<Widget>[
            const SizedBox(height: Spacing.md),
            TextField(
              key: kOnboardingPinFieldKey,
              obscureText: true,
              maxLength: 4,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: (value) => _draft.parentalPin = value,
              decoration: const InputDecoration(labelText: '4-digit PIN'),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              key: kOnboardingSeedWordsFieldKey,
              onChanged: (value) => _draft.blockedSeedWords = value
                  .split(',')
                  .map((word) => word.trim())
                  .where((word) => word.isNotEmpty)
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
        index: 7,
        title: 'AI features',
        subtitle: 'Optional — bring your own key, everything stays local.',
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              color: context.wavelyColors.surface,
              borderRadius: AppRadii.bLg,
              border: Border.all(color: context.wavelyColors.borderGlass),
            ),
            child: SwitchListTile(
              value: _draft.aiConsent,
              onChanged: (consent) =>
                  setState(() => _draft.aiConsent = consent),
              secondary: Icon(
                Icons.auto_awesome_rounded,
                color: context.wavelyColors.accentColors.accent,
              ),
              title: const Text('Enable AI features'),
              subtitle: const Text('Mood-aware queues and library chat'),
            ),
          ),
          const SizedBox(height: Spacing.md),
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
        index: 8,
        title: 'Music folders',
        subtitle: 'Pick where your audio lives — the first scan starts '
            'right after setup.',
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
            runSpacing: Spacing.sm,
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
        index: 9,
        title: 'All set',
        subtitle: 'Everything below is applied when you press Finish — '
            'backing out keeps your previous settings untouched.',
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              color: context.wavelyColors.surface,
              borderRadius: AppRadii.bLg,
              border: Border.all(color: context.wavelyColors.borderGlass),
            ),
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
        ],
      );

  Widget _summaryLine(String text) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: Text(
          text,
          style: WavelyTypography.body14(
            color: context.wavelyColors.textPrimary,
          ),
        ),
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
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: _backdrop(colors)),
          SafeArea(
            child: Column(
              children: <Widget>[
                _header(colors),
                ClipRRect(
                  borderRadius: AppRadii.bPill,
                  child: LinearProgressIndicator(
                    value: (_page + 1) / _pageCount,
                    minHeight: 3,
                    backgroundColor: colors.borderGlass,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colors.accentColors.accent,
                    ),
                  ),
                ),
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
        ],
      ),
    );
  }
}

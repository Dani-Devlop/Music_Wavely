/// Equalizer & effects screen (Phase 8).
///
/// Musicolet-parity "sound" screen combining:
/// - 5-band equalizer with master toggle, built-in + user presets
///   (save/delete), per-band sliders;
/// - BassBoost, Virtualizer (surround), Reverb presets, Balance L/R,
///   Force mono;
/// - ReplayGain: mode (off/track/album), pre-amp, batch scan with
///   progress + cancel;
/// - Crossfade (0–30 s) + gapless;
/// - per-output-device profile indicator (profiles auto-switch on device
///   change).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/playback/effects/audio_effects.dart';
import 'package:wavely/playback/effects/effects_filter.dart';
import 'package:wavely/playback/profiles/audio_engine_controller.dart';
import 'package:wavely/playback/profiles/audio_profile_codec.dart';
import 'package:wavely/playback/equalizer/eq_presets.dart';
import 'package:wavely/playback/replaygain/replay_gain_math.dart';
import 'package:wavely/playback/replaygain/replay_gain_scan_service.dart';
import 'package:wavely/core/audio/ffmpeg_executor.dart';

/// Route path registered in the router.
const String kAudioSettingsRoute = '/settings/audio';

/// ReplayGain scan service (single instance).
final replayGainScanServiceProvider = Provider<ReplayGainScanService>(
  (ref) => ReplayGainScanService(
    executor: const FFmpegKitExecutor(),
    db: ref.watch(databaseProvider),
  ),
);

/// Reactive scan progress.
final replayGainScanStateProvider = StreamProvider<ReplayGainScanState>(
  (ref) => ref.watch(replayGainScanServiceProvider).stateStream,
);

/// Equalizer & effects screen.
class AudioSettingsScreen extends ConsumerWidget {
  const AudioSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final AudioEngineState engineState =
        ref.watch(audioEngineControllerProvider);

    return Scaffold(
      key: const ValueKey<String>('audio-settings-screen'),
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        title: Text(
          'Equalizer & effects',
          style: WavelyTypography.title20(color: colors.textPrimary),
        ),
      ),
      body: !engineState.ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              // Generous cacheExtent: every section stays built so tests
              // can find widgets before scrolling (settings-screen
              // pattern).
              cacheExtent: 4000,
              padding: const EdgeInsets.all(Spacing.lg),
              children: <Widget>[
                _SectionGroup(
                  title: 'Output profile',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Settings are remembered per output device '
                        '(active: ${engineState.outputDeviceLabel}).',
                        style: WavelyTypography.caption12(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                _EqSection(engineState: engineState),
                const SizedBox(height: Spacing.lg),
                _EffectsSection(engineState: engineState),
                const SizedBox(height: Spacing.lg),
                _ReplayGainSection(),
                const SizedBox(height: Spacing.lg),
                _TransitionsSection(engineState: engineState),
                const SizedBox(height: Spacing.lg),
              ],
            ),
    );
  }
}

/// Token-styled settings group (matches the settings screen pattern).
class _SectionGroup extends StatelessWidget {
  const _SectionGroup({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.bLg,
        border: Border.all(color: colors.borderGlass),
      ),
      // ListTile paints on the nearest Material; without this the
      // decorated container hides ink splashes (framework assertion).
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: WavelyTypography.body14Medium(color: colors.textPrimary),
            ),
            const SizedBox(height: Spacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// 5-band EQ + presets.
class _EqSection extends ConsumerWidget {
  const _EqSection({required this.engineState});

  final AudioEngineState engineState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final AudioEngineController controller =
        ref.read(audioEngineControllerProvider.notifier);
    final AudioSettingsState settings = engineState.settings;

    return _SectionGroup(
      title: 'Equalizer',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            key: const ValueKey<String>('eq-enabled'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Enable equalizer',
              style: WavelyTypography.body14(color: colors.textPrimary),
            ),
            subtitle: engineState.eqSupported
                ? null
                : Text(
                    'Not supported by the active engine',
                    style:
                        WavelyTypography.caption12(color: colors.textSecondary),
                  ),
            value: settings.eqEnabled,
            onChanged: (bool value) => controller.setEqEnabled(value),
          ),
          SizedBox(
            height: 170,
            child: Row(
              children: <Widget>[
                for (var i = 0; i < 5; i++)
                  Expanded(
                    child: _BandSlider(
                      key: ValueKey<String>('eq-band-$i'),
                      band: i,
                      gain: i < settings.eqGains.length
                          ? settings.eqGains[i]
                          : 0.0,
                      onChanged: (double value) =>
                          controller.setEqGain(i, value),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),
          const _PresetPicker(),
        ],
      ),
    );
  }
}

/// One vertical band slider with its frequency label.
class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.band,
    required this.gain,
    required this.onChanged,
    super.key,
  });

  final int band;
  final double gain;
  final ValueChanged<double> onChanged;

  static const List<String> _labels = <String>[
    '60',
    '230',
    '910',
    '3.6k',
    '14k',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Column(
      children: <Widget>[
        Expanded(
          child: RotatedBox(
            quarterTurns: -1,
            child: Slider(
              value: gain.clamp(-12.0, 12.0),
              min: -12,
              max: 12,
              divisions: 48,
              label: '${gain.toStringAsFixed(1)} dB',
              onChanged: onChanged,
            ),
          ),
        ),
        Text(
          band < _labels.length ? '${_labels[band]} Hz' : '',
          style: WavelyTypography.caption12(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// Built-in + user preset picker with save/delete.
class _PresetPicker extends ConsumerStatefulWidget {
  const _PresetPicker();

  @override
  ConsumerState<_PresetPicker> createState() => _PresetPickerState();
}

class _PresetPickerState extends ConsumerState<_PresetPicker> {
  Future<Map<String, List<double>>>? _presetsFuture;

  @override
  void initState() {
    super.initState();
    _presetsFuture = _loadPresets();
  }

  Future<Map<String, List<double>>> _loadPresets() async {
    final AudioEngineController controller =
        ref.read(audioEngineControllerProvider.notifier);
    final Map<String, List<double>> presets = <String, List<double>>{
      for (final preset in kBuiltinEqPresets)
        'builtin:${preset.name}': preset.gainsDb,
    };
    // User presets live per device in the eq_presets table; resolve via
    // the controller's stored profiles' preset key namespace.
    final List<AudioProfileRow> rows = await controller.storedProfiles();
    for (final row in rows) {
      if (row.eqPresetKey.isNotEmpty &&
          !row.eqPresetKey.startsWith('builtin:')) {
        // Stored profile snapshots double as user presets.
        try {
          final gains = await _gainsFromProfileRow(row);
          if (gains != null) {
            presets[row.eqPresetKey] = gains;
          }
        } on Object {
          // Skip malformed rows.
        }
      }
    }
    return presets;
  }

  Future<List<double>?> _gainsFromProfileRow(AudioProfileRow row) async {
    // Rows carry the canonical JSON through the codec.
    return AudioProfileGainsBridge.decode(row.eqGainsJson);
  }

  Future<void> _apply(String key) async {
    final AudioEngineController controller =
        ref.read(audioEngineControllerProvider.notifier);
    final presets = await _presetsFuture ?? const <String, List<double>>{};
    final List<double>? gains =
        await controller.applyEqPreset(key, (_) async => presets[key]);
    if (gains != null && mounted) {
      setState(() {
        _presetsFuture = _loadPresets();
      });
    }
  }

  Future<void> _save() async {
    final TextEditingController nameCtrl = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Save preset'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Preset name'),
          onSubmitted: (String value) =>
              Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(nameCtrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) {
      return;
    }
    final AudioEngineController controller =
        ref.read(audioEngineControllerProvider.notifier);
    final List<double> currentGains = List<double>.of(
      ref.read(audioEngineControllerProvider).settings.eqGains,
    );
    await controller.applyEqPreset(name, (_) async => currentGains);
    if (mounted) {
      setState(() {
        _presetsFuture = _loadPresets();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final AudioEngineState engineState =
        ref.watch(audioEngineControllerProvider);
    return Row(
      children: <Widget>[
        Expanded(
          child: FutureBuilder<Map<String, List<double>>>(
            future: _presetsFuture,
            builder: (
              BuildContext context,
              AsyncSnapshot<Map<String, List<double>>> snapshot,
            ) {
              final Map<String, List<double>> presets =
                  snapshot.data ?? const <String, List<double>>{};
              return DropdownButton<String>(
                key: const ValueKey<String>('eq-preset-dropdown'),
                isExpanded: true,
                value: engineState.settings.eqPresetKey.isEmpty
                    ? null
                    : (presets.containsKey(engineState.settings.eqPresetKey)
                        ? engineState.settings.eqPresetKey
                        : null),
                hint: Text(
                  'Preset',
                  style: WavelyTypography.body14(color: colors.textSecondary),
                ),
                items: <DropdownMenuItem<String>>[
                  for (final String key in presets.keys)
                    DropdownMenuItem<String>(
                      value: key,
                      child: Text(
                        key.startsWith('builtin:')
                            ? key.substring('builtin:'.length)
                            : key,
                        style: WavelyTypography.body14(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                ],
                onChanged: (String? key) {
                  if (key != null) {
                    unawaited(_apply(key));
                  }
                },
              );
            },
          ),
        ),
        IconButton(
          key: const ValueKey<String>('eq-preset-save'),
          tooltip: 'Save current as preset',
          icon: const Icon(Icons.save_outlined),
          onPressed: _save,
        ),
      ],
    );
  }
}

/// Bridges gain JSON decoding without leaking the codec into the UI.
abstract final class AudioProfileGainsBridge {
  static List<double>? decode(String json) {
    try {
      final Object? decoded = jsonDecode(json);
      return decoded is List
          ? <double>[for (final Object? v in decoded) (v as num).toDouble()]
          : null;
    } on Object {
      return null;
    }
  }
}

/// BassBoost / Virtualizer / Reverb / Balance / Mono.
class _EffectsSection extends ConsumerWidget {
  const _EffectsSection({required this.engineState});

  final AudioEngineState engineState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final AudioEffectsState effects = engineState.settings.effects;
    final AudioEngineController controller =
        ref.read(audioEngineControllerProvider.notifier);

    return _SectionGroup(
      title: 'Effects',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!engineState.effectsSupported)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Text(
                'Effects are applied through the audio engine when the '
                'platform supports them.',
                style: WavelyTypography.caption12(color: colors.textSecondary),
              ),
            ),
          _SliderRow(
            key: const ValueKey<String>('effect-bassboost'),
            label: 'BassBoost',
            value: effects.bassBoost.toDouble(),
            max: 100,
            display: '${effects.bassBoost}%',
            onChanged: (double value) =>
                controller.setBassBoost(value.round()),
          ),
          _SliderRow(
            key: const ValueKey<String>('effect-virtualizer'),
            label: 'Virtualizer (Surround)',
            value: effects.virtualizer.toDouble(),
            max: 100,
            display: '${effects.virtualizer}%',
            onChanged: (double value) =>
                controller.setVirtualizer(value.round()),
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButton<String>(
                  key: const ValueKey<String>('effect-reverb'),
                  isExpanded: true,
                  value: effects.reverbPreset.isEmpty
                      ? null
                      : effects.reverbPreset,
                  hint: Text(
                    'Reverb: off',
                    style:
                        WavelyTypography.body14(color: colors.textSecondary),
                  ),
                  items: <DropdownMenuItem<String>>[
                    for (final String preset in kReverbPresets)
                      DropdownMenuItem<String>(
                        value: preset,
                        child: Text(
                          preset,
                          style: WavelyTypography.body14(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                  ],
                  onChanged: (String? preset) =>
                      controller.setReverbPreset(preset ?? ''),
                ),
              ),
              if (effects.reverbPreset.isNotEmpty)
                IconButton(
                  tooltip: 'Reverb off',
                  icon: const Icon(Icons.close),
                  onPressed: () => controller.setReverbPreset(''),
                ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          _SliderRow(
            key: const ValueKey<String>('effect-balance'),
            label: 'Balance',
            value: effects.balance,
            min: -1,
            max: 1,
            display: effects.balance == 0
                ? 'Center'
                : effects.balance < 0
                    ? 'L ${(-effects.balance * 100).round()}%'
                    : 'R ${(effects.balance * 100).round()}%',
            onChanged: controller.setBalance,
          ),
          SwitchListTile(
            key: const ValueKey<String>('effect-mono'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Force mono',
              style: WavelyTypography.body14(color: colors.textPrimary),
            ),
            value: effects.forceMono,
            onChanged: controller.setForceMono,
          ),
        ],
      ),
    );
  }
}

/// Horizontal slider row with label + live value.
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.display,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              label,
              style: WavelyTypography.body14(color: colors.textPrimary),
            ),
            Text(
              display,
              style: WavelyTypography.caption12(color: colors.textSecondary),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// ReplayGain mode / pre-amp / scan.
class _ReplayGainSection extends ConsumerStatefulWidget {
  const _ReplayGainSection();

  @override
  ConsumerState<_ReplayGainSection> createState() =>
      _ReplayGainSectionState();
}

class _ReplayGainSectionState extends ConsumerState<_ReplayGainSection> {
  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final AudioEngineState engineState =
        ref.watch(audioEngineControllerProvider);
    final AudioEngineController controller =
        ref.read(audioEngineControllerProvider.notifier);
    final ReplayGainScanService scanner =
        ref.watch(replayGainScanServiceProvider);
    final ReplayGainScanState scan =
        ref.watch(replayGainScanStateProvider).value ??
            scanner.currentState;

    return _SectionGroup(
      title: 'ReplayGain',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SegmentedButton<ReplayGainMode>(
            key: const ValueKey<String>('rg-mode'),
            segments: const <ButtonSegment<ReplayGainMode>>[
              ButtonSegment<ReplayGainMode>(
                value: ReplayGainMode.off,
                label: Text('Off'),
              ),
              ButtonSegment<ReplayGainMode>(
                value: ReplayGainMode.track,
                label: Text('Track'),
              ),
              ButtonSegment<ReplayGainMode>(
                value: ReplayGainMode.album,
                label: Text('Album'),
              ),
            ],
            selected: <ReplayGainMode>{engineState.settings.replayGainMode},
            onSelectionChanged: (Set<ReplayGainMode> selection) =>
                controller.setReplayGainMode(selection.first),
          ),
          const SizedBox(height: Spacing.md),
          _SliderRow(
            key: const ValueKey<String>('rg-preamp'),
            label: 'Pre-amp',
            value: engineState.settings.replayGainPreampDb,
            min: -6,
            max: 6,
            display:
                '${engineState.settings.replayGainPreampDb.toStringAsFixed(1)} dB',
            onChanged: controller.setReplayGainPreamp,
          ),
          const SizedBox(height: Spacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey<String>('rg-scan-button'),
                  onPressed: scan.running
                      ? null
                      : () => unawaited(scanner.scanLibrary()),
                  icon: const Icon(Icons.graphic_eq_rounded),
                  label: const Text('Scan library'),
                ),
              ),
              if (scan.running) ...<Widget>[
                const SizedBox(width: Spacing.sm),
                OutlinedButton(
                  key: const ValueKey<String>('rg-scan-cancel'),
                  onPressed: scanner.cancel,
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
          if (scan.running || scan.isDone) ...<Widget>[
            const SizedBox(height: Spacing.md),
            LinearProgressIndicator(value: scan.progress),
            const SizedBox(height: Spacing.xs),
            Text(
              scan.running
                  ? 'Analyzing: ${scan.currentTrack ?? '…'} '
                      '(${scan.completed + scan.failed}/${scan.total})'
                  : 'Scan complete: ${scan.completed} ok, '
                      '${scan.failed} failed',
              style: WavelyTypography.caption12(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Crossfade + gapless.
class _TransitionsSection extends ConsumerWidget {
  const _TransitionsSection({required this.engineState});

  final AudioEngineState engineState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final AudioEngineController controller =
        ref.read(audioEngineControllerProvider.notifier);
    final AudioSettingsState settings = engineState.settings;

    return _SectionGroup(
      title: 'Transitions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SliderRow(
            key: const ValueKey<String>('transition-crossfade'),
            label: 'Crossfade',
            value: settings.crossfadeSeconds.toDouble(),
            max: 30,
            display: settings.crossfadeSeconds == 0
                ? 'Off'
                : '${settings.crossfadeSeconds}s',
            onChanged: (double value) =>
                controller.setCrossfadeSeconds(value.round()),
          ),
          SwitchListTile(
            key: const ValueKey<String>('transition-gapless'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Gapless playback',
              style: WavelyTypography.body14(color: colors.textPrimary),
            ),
            subtitle: Text(
              'Advance to the next track with no fade',
              style: WavelyTypography.caption12(color: colors.textSecondary),
            ),
            value: settings.gapless,
            onChanged: controller.setGapless,
          ),
        ],
      ),
    );
  }
}

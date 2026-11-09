/// Dedicated Musicolet-style Equalizer screen (v1.0.2 Android UI).
///
/// Owner spec: 10-band vertical sliders, green accent colors, a
/// "Custom" preset label and a Save (bookmark-add) icon.
///
/// This screen drives the engine's REAL [EqualizerControl] capability
/// directly: the desktop engine exposes a synthetic 10-band EQ (31 Hz …
/// 16 kHz) rendered 1:1, while Android renders the device-reported band
/// count (usually 5) — exactly how Musicolet behaves on real hardware.
/// The screen never touches the playback internals; every slider writes
/// straight through `setEqualizerBandGain`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/player/presentation/musicolet_palette.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/equalizer/eq_presets.dart';
import 'package:wavely/playback/equalizer/equalizer_control.dart';
import 'package:wavely/playback/profiles/audio_engine_controller.dart';

/// Route path registered in the router (Now Playing EQ button + Settings).
const String kEqualizerRoute = '/equalizer';

/// shared_preferences key for user-saved EQ presets.
const String kUserEqPresetsKey = 'wavely.userEqPresets.v1';

/// shared_preferences key for the last applied 10-band curve.
const String kDedicatedEqCurveKey = 'wavely.dedicatedEqCurve.v1';

/// Resolves the engine's live equalizer facts (band count + frequencies).
final equalizerInfoProvider = FutureProvider<EqualizerInfo?>((ref) async {
  // Declared as Object? so the `is EqualizerControl` type promotion can
  // apply (EqualizerControl is a capability interface, not a PlaybackEngine
  // supertype — same pattern as AudioEngineController._applyToEngine).
  final Object? engine = ref.watch(playbackEngineProvider);
  if (engine is EqualizerControl) {
    if (!engine.equalizerAvailable) {
      return null;
    }
    return engine.queryEqualizer();
  }
  return null;
});

/// The Musicolet-style equalizer screen.
class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});

  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  /// Local working curve (dB per band of the engine layout).
  List<double> _gains = const <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

  Map<String, List<double>>? _presets;
  String _activePresetLabel = 'Custom';
  bool _enabled = true;
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    unawaited(_hydrate());
    unawaited(_loadPresets());
  }

  /// Restores the last curve + pushes it to the engine, and mirrors the
  /// enable state through the engine controller (one source of truth for
  /// the Audio settings toggle).
  Future<void> _hydrate() async {
    List<double>? restored;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kDedicatedEqCurveKey);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List<Object?>)
            .map((g) => (g as num).toDouble())
            .toList(growable: false);
        if (list.isNotEmpty) {
          restored = list;
        }
      }
    } on Object {
      restored = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _gains = restored ?? _gains;
      _hydrated = true;
    });
    await _pushCurve();
  }

  Future<void> _pushCurve() async {
    final Object? engine = ref.read(playbackEngineProvider);
    ref.read(audioEngineControllerProvider.notifier).setEqEnabled(_enabled);
    if (engine is! EqualizerControl) {
      return;
    }
    await engine.setEqualizerEnabled(enabled: _enabled);
    for (var i = 0; i < _gains.length; i++) {
      await engine.setEqualizerBandGain(i, _gains[i]);
    }
  }

  Future<void> _persistCurve() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kDedicatedEqCurveKey, jsonEncode(_gains));
    } on Object {
      // Non-fatal: the curve stays engine-live for this session.
    }
  }

  Future<void> _loadPresets() async {
    final presets = <String, List<double>>{
      for (final preset in kBuiltinEqPresets) preset.name: preset.gainsDb,
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kUserEqPresetsKey);
      if (raw != null && raw.isNotEmpty) {
        presets.addAll(
          (jsonDecode(raw) as Map<String, Object?>).map(
            (k, v) => MapEntry(
              k,
              <double>[
                for (final g in (v as List<Object?>)) (g as num).toDouble(),
              ],
            ),
          ),
        );
      }
    } on Object {
      // Corrupt store — built-ins only.
    }
    if (!mounted) {
      return;
    }
    setState(() => _presets = presets);
  }

  Future<void> _savePreset() async {
    final controller = TextEditingController(text: 'My preset');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: MusicoletColors.sheet,
        title: Text(
          'Save preset',
          style: WavelyTypography.title18(color: MusicoletColors.text),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: WavelyTypography.body14(color: MusicoletColors.text),
          decoration: const InputDecoration(
            labelText: 'Preset name',
            labelStyle: TextStyle(color: MusicoletColors.textDim),
          ),
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MusicoletColors.green,
              foregroundColor: Colors.black,
            ),
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kUserEqPresetsKey);
      final Map<String, Object?> existing = raw == null || raw.isEmpty
          ? <String, Object?>{}
          : (jsonDecode(raw) as Map<String, Object?>);
      existing[name] = List<double>.of(_gains);
      await prefs.setString(kUserEqPresetsKey, jsonEncode(existing));
    } on Object {
      return;
    }
    await _loadPresets();
    if (mounted) {
      setState(() => _activePresetLabel = name);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: MusicoletColors.greenDark,
          content: Text('Preset "$name" saved'),
        ),
      );
    }
  }

  void _applyPreset(String name, List<double> gains) {
    final info = ref.read(equalizerInfoProvider).value;
    final bandCount = info?.bandCount ?? 10;
    setState(() {
      _gains = EqualizerGains.resample(gains, bandCount);
      _activePresetLabel = name;
      _enabled = true;
    });
    unawaited(_pushCurve());
    unawaited(_persistCurve());
  }

  @override
  Widget build(BuildContext context) {
    final engineState = ref.watch(audioEngineControllerProvider);
    final info = ref.watch(equalizerInfoProvider).value;
    final bandCount = info?.bandCount ?? 10;
    final frequencies = (info?.bandFrequencies.isNotEmpty ?? false)
        ? info!.bandFrequencies
        : kStandardEqFrequencies;
    final minGain = info?.minGainDb ?? kEqMinGainDb;
    final maxGain = info?.maxGainDb ?? kEqMaxGainDb;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: MusicoletColors.text,
        elevation: 0,
        title: Text(
          'Equalizer',
          style: WavelyTypography.title18(color: MusicoletColors.text),
        ),
        actions: <Widget>[
          IconButton(
            key: const Key('eq-save-preset'),
            tooltip: 'Save preset',
            icon: const Icon(Icons.bookmark_add_outlined,
                color: MusicoletColors.green),
            onPressed: () => unawaited(_savePreset()),
          ),
        ],
      ),
      body: !engineState.ready
          ? const Center(
              child:
                  CircularProgressIndicator(color: MusicoletColors.green),
            )
          : ListView(
              padding: const EdgeInsets.all(Spacing.lg),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _activePresetLabel,
                        style: WavelyTypography.title20(
                          color: MusicoletColors.green,
                        ),
                      ),
                    ),
                    if (_presets != null)
                      PopupMenuButton<String>(
                        key: const Key('eq-screen-presets'),
                        tooltip: 'Presets',
                        icon: const Icon(Icons.tune,
                            color: MusicoletColors.green),
                        onSelected: (name) {
                          final gains = _presets![name];
                          if (gains != null) {
                            _applyPreset(name, gains);
                          }
                        },
                        itemBuilder: (context) => <PopupMenuEntry<String>>[
                          for (final name in _presets!.keys)
                            PopupMenuItem<String>(
                              value: name,
                              child: Text(
                                name,
                                style: WavelyTypography.body14(
                                  color: MusicoletColors.text,
                                ),
                              ),
                            ),
                        ],
                      ),
                    Switch(
                      key: const Key('eq-screen-enabled'),
                      activeColor: MusicoletColors.green,
                      value: _enabled,
                      onChanged: (value) {
                        setState(() => _enabled = value);
                        unawaited(_pushCurve());
                      },
                    ),
                  ],
                ),
                if (!engineState.eqSupported)
                  const Padding(
                    padding: EdgeInsets.only(bottom: Spacing.md),
                    child: Text(
                      'The active engine cannot apply an equalizer — '
                      'sliders will still store your curve.',
                      style: TextStyle(color: MusicoletColors.textDim),
                    ),
                  ),
                const SizedBox(height: Spacing.lg),
                SizedBox(
                  height: 260,
                  child: _hydrated
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            for (var i = 0; i < bandCount; i++)
                              Expanded(
                                child: _BandSlider(
                                  key:
                                      ValueKey<String>('eq-screen-band-$i'),
                                  frequency: i < frequencies.length
                                      ? frequencies[i]
                                      : 0,
                                  gain: i < _gains.length
                                      ? _gains[i]
                                      : 0.0,
                                  minGain: minGain,
                                  maxGain: maxGain,
                                  onChanged: (value) {
                                    final next = List<double>.of(_gains);
                                    while (next.length < bandCount) {
                                      next.add(0);
                                    }
                                    next[i] = value;
                                    setState(() {
                                      _gains = next;
                                      _activePresetLabel = 'Custom';
                                    });
                                    unawaited(_pushCurve());
                                    unawaited(_persistCurve());
                                  },
                                ),
                              ),
                          ],
                        )
                      : const Center(
                          child: CircularProgressIndicator(
                            color: MusicoletColors.green,
                          ),
                        ),
                ),
                const SizedBox(height: Spacing.lg),
                Center(
                  child: Text(
                    '$bandCount-band equalizer · '
                    '${minGain.round()} … +${maxGain.round()} dB',
                    style: WavelyTypography.caption12(
                      color: MusicoletColors.textDim,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// One green vertical band slider with its frequency label.
class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.frequency,
    required this.gain,
    required this.minGain,
    required this.maxGain,
    required this.onChanged,
    super.key,
  });

  final double frequency;
  final double gain;
  final double minGain;
  final double maxGain;
  final ValueChanged<double> onChanged;

  static String _label(double hz) {
    if (hz >= 1000) {
      final khz = hz / 1000;
      return khz == khz.roundToDouble()
          ? '${khz.round()}k'
          : '${khz.toStringAsFixed(1)}k';
    }
    return hz.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: RotatedBox(
            quarterTurns: -1,
            child: Slider(
              value: gain.clamp(minGain, maxGain),
              min: minGain,
              max: maxGain,
              divisions: 48,
              activeColor: MusicoletColors.green,
              inactiveColor: MusicoletColors.divider,
              label: '${gain.toStringAsFixed(1)} dB',
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          _label(frequency),
          style: WavelyTypography.caption12(
            color: MusicoletColors.textDim,
          ),
        ),
      ],
    );
  }
}

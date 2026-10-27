import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/playback/shuffle/advanced_shuffle.dart';

/// Modal bottom sheet for editing the advanced shuffle [ShuffleConfig] (B7).
///
/// Comma-separated tag editors keep the sheet compact; chips would need a
/// full picker flow for every dimension. The QueueManager consumes the
/// config through the composition root on the next `toggleShuffle`.
class ShuffleConfigSheet extends ConsumerStatefulWidget {
  /// Creates the sheet (show via `showModalBottomSheet`).
  const ShuffleConfigSheet({super.key});

  @override
  ConsumerState<ShuffleConfigSheet> createState() => _ShuffleConfigSheetState();
}

class _ShuffleConfigSheetState extends ConsumerState<ShuffleConfigSheet> {
  late final TextEditingController _languages;
  late final TextEditingController _genres;
  late final TextEditingController _artists;
  late double _weighting;
  late bool _includeExplicit;

  @override
  void initState() {
    super.initState();
    final config = ref.read(advancedShuffleConfigProvider);
    _languages = TextEditingController(text: config.blockedLanguages.join(', '));
    _genres = TextEditingController(text: config.blockedGenres.join(', '));
    _artists = TextEditingController(text: config.blockedArtistIds.join(', '));
    _weighting = config.weighting;
    _includeExplicit = config.includeExplicit;
  }

  @override
  void dispose() {
    _languages.dispose();
    _genres.dispose();
    _artists.dispose();
    super.dispose();
  }

  Set<String> _tags(TextEditingController controller) => controller.text
      .split(',')
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toSet();

  void _apply() {
    final previous = ref.read(advancedShuffleConfigProvider);
    ref.read(advancedShuffleConfigProvider.notifier).update(
          ShuffleConfig(
            allowedLanguages: previous.allowedLanguages,
            allowedGenres: previous.allowedGenres,
            allowedArtistIds: previous.allowedArtistIds,
            blockedLanguages: _tags(_languages),
            blockedGenres: _tags(_genres),
            blockedArtistIds: _tags(_artists),
            includeExplicit: _includeExplicit,
            weighting: _weighting,
            noRepeatWindow: previous.noRepeatWindow,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Advanced shuffle', style: WavelyTypography.title18()),
          const SizedBox(height: Spacing.md),
          _field(context, 'Never play languages', _languages, 'en, fa'),
          _field(context, 'Never play genres', _genres, 'metal, horrorcore'),
          _field(context, 'Never play artists', _artists, 'artist one'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Include explicit tracks'),
            value: _includeExplicit,
            onChanged: (v) => setState(() => _includeExplicit = v),
          ),
          Text(
            'Play-count weighting: ${_weighting.toStringAsFixed(1)}',
            style: WavelyTypography.caption12(color: colors.textSecondary),
          ),
          RadioListTile<double>(
            title: const Text('Uniform (pure shuffle)'),
            value: 0,
            groupValue: _weighting,
            onChanged: (v) => setState(() => _weighting = v ?? 0),
          ),
          RadioListTile<double>(
            title: const Text('Favour play counts'),
            value: 0.75,
            groupValue: _weighting,
            onChanged: (v) => setState(() => _weighting = v ?? 0.75),
          ),
          const SizedBox(height: Spacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _apply,
              child: const Text('Apply'),
            ),
          ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context,
    String label,
    TextEditingController controller,
    String hint,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Spacing.md),
        child: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
      );
}

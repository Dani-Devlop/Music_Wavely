import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 10.4: "What's New" changelog presentation.
///
/// The content map covers every shipped beta; the sheet shows the entry
/// for the running version when it has not been seen yet (compare-and-set
/// through a SharedPreferences key — [maybeShowWhatsNew] both decides and
/// records).
abstract final class WhatsNew {
  /// Prefs key storing the last version the sheet was shown for.
  static const String prefsKey = 'wavely.whatsnew.seen';

  /// Version → bullet list. Keys are plain version strings (no `v`).
  static const Map<String, List<String>> changelog = <String, List<String>>{
    '1.0.1': <String>[
      'Total Musicolet parity: 20 multi-queues, 9 library tabs, '
          '3-source lyrics, bookmarks, A-B repeat and the sleep timer.',
      'Spotify-style Online tab and the 13-field batch tag editor plus '
          'the audio cutter with set-as-ringtone.',
      '5-band EQ, ReplayGain, crossfade, gapless and per-device audio '
          'profiles.',
      'Lock-screen playback, three home-screen widgets, quick-settings '
          'tile and headset FF/rewind rules.',
      'AMOLED black mode, adaptive accent from album art, blur and '
          'corner-radius sliders, mini-player gestures.',
      'Persian (فارسی) translation with full RTL support and a fresh '
          'neon-glass logo.',
    ],
  };

  /// True when [version] has not been shown yet in [prefs].
  static bool isUnseen(SharedPreferences prefs, String version) =>
      prefs.getString(prefsKey) != version;

  /// Marks [version] as seen.
  static Future<void> markSeen(SharedPreferences prefs, String version) =>
      prefs.setString(prefsKey, version);

  /// Content for [version] (null when no entry ships for it).
  static List<String>? contentFor(String version) => changelog[version];
}

/// Shows the "What's New" bottom sheet when the running [version] has not
/// been presented before, then records the version. Safe to call once per
/// process (the main-shell bootstrap does exactly that).
Future<void> maybeShowWhatsNew(
  BuildContext context,
  SharedPreferences prefs,
  String version,
) async {
  if (!WhatsNew.isUnseen(prefs, version)) {
    return;
  }
  await WhatsNew.markSeen(prefs, version);
  final content = WhatsNew.contentFor(version);
  if (content == null || !context.mounted) {
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => WhatsNewSheet(
      version: version,
      bullets: content,
      onClose: () => Navigator.of(sheetContext).pop(),
    ),
  );
}

/// "What's New" content sheet (Phase 10.4).
class WhatsNewSheet extends StatelessWidget {
  /// Creates the sheet for [version] with [bullets].
  const WhatsNewSheet({
    required this.version,
    required this.bullets,
    required this.onClose,
    super.key,
  });

  final String version;
  final List<String> bullets;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  "What's New in $version",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  key: const ValueKey<String>('whats-new-close'),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: bullets.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Icon(
                          Icons.music_note_rounded,
                          size: 14,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          bullets[index],
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey<String>('whats-new-continue'),
                onPressed: onClose,
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

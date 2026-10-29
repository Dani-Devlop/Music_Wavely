/// Authored, awaiting local run (Task 2-f).
///
/// [TrackTile] smoke test (plus the shared [WavelyCoverFallback]): renders
/// title/artist/duration, the explicit badge, the source badge, the
/// selection highlight, an optional trailing slot and the gradient cover
/// fallback initial; tap and long-press callbacks fire; renders under BOTH
/// the light and dark Wavely themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/design_system/components/explicit_badge.dart';
import 'package:wavely/design_system/components/track_tile.dart';
import 'package:wavely/domain/entities/entities.dart';

import '../helpers/pump_theme.dart';

Track _track({
  bool explicit = false,
  String sourceId = 'local',
}) =>
    Track(
      id: 3,
      sourceId: sourceId,
      sourceTrackId: 'tt-3',
      title: 'Neon Rivers',
      artist: 'Velvet Echo',
      durationMs: 203000, // 03:23
      format: 'mp3',
      addedAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
      playCount: 5,
      explicit: explicit,
    );

void main() {
  for (final dark in <bool>[false, true]) {
    String label(bool d) => d ? 'dark' : 'light';

    testWidgets('basic tile: text content + cover fallback initial '
        '(${label(dark)} theme)', (tester) async {
      await pumpThemed(
        tester,
        dark: dark,
        child: TrackTile(track: _track(), onTap: () {}),
      );
      expect(find.text('Neon Rivers'), findsOneWidget);
      expect(find.text('Velvet Echo'), findsOneWidget);
      expect(find.text('03:23'), findsOneWidget);
      // Gradient fallback shows the title initial (no coverPath).
      expect(find.text('N'), findsOneWidget);
      expect(find.byType(ExplicitBadge), findsNothing);
    });

    testWidgets('explicit + source badges, selection key and trailing '
        'slot (${label(dark)} theme)', (tester) async {
      await pumpThemed(
        tester,
        dark: dark,
        child: TrackTile(
          track: _track(explicit: true, sourceId: 'spotify'),
          showSourceBadge: true,
          selected: true,
          trailing: const Icon(Icons.favorite_border),
        ),
      );
      expect(find.byType(ExplicitBadge), findsOneWidget);
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('wavely.trackTile.selected')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });

    testWidgets('tap and long-press callbacks fire (${label(dark)} '
        'theme)', (tester) async {
      var taps = 0;
      var longPresses = 0;
      await pumpThemed(
        tester,
        dark: dark,
        child: TrackTile(
          track: _track(),
          onTap: () => taps++,
          onLongPress: () => longPresses++,
        ),
      );
      await tester.tap(find.text('Neon Rivers'));
      await tester.pump();
      expect(taps, 1);
      await tester.longPress(find.text('Neon Rivers'));
      await tester.pump();
      expect(longPresses, 1);
    });
  }
}

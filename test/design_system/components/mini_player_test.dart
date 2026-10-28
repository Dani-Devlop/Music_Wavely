/// Authored, awaiting local run (Task 2-f).
///
/// [MiniPlayer] smoke test (biggest surface): transport callbacks — the
/// REAL callback names are `onPlayPause`, `onNext` and `onTap` — fire from
/// their buttons, the play/pause icon and tooltip flip with [isPlaying],
/// the progress strip reflects position/duration, the null-track state
/// shows 'Nothing playing', and everything renders under BOTH the light
/// and dark Wavely themes (ProviderScope + reduce-transparency override
/// because the player stands on a GlassCard).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavely/design_system/components/mini_player.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';

import '../helpers/pump_theme.dart';

Track _track() => Track(
      id: 7,
      sourceId: 'local',
      sourceTrackId: 'mp-7',
      title: 'Midnight Transit',
      artist: 'Cedar Waves',
      durationMs: 214000,
      format: 'mp3',
      addedAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

List<Override> _overrides() => <Override>[
      reduceTransparencyProvider.overrideWithValue(false),
    ];

String _label(bool dark) => dark ? 'dark' : 'light';

void main() {
  for (final dark in <bool>[false, true]) {
    testWidgets('with a track: title/artist render and transport '
        'callbacks fire (${_label(dark)} theme)', (tester) async {
      var playPauseTaps = 0;
      var nextTaps = 0;
      var tileTaps = 0;
      await pumpThemed(
        tester,
        dark: dark,
        overrides: _overrides(),
        child: MiniPlayer(
          track: _track(),
          isPlaying: true,
          position: const Duration(seconds: 53),
          duration: const Duration(seconds: 212),
          onPlayPause: () => playPauseTaps++,
          onTap: () => tileTaps++,
          onNext: () => nextTaps++,
        ),
      );
      expect(find.text('Midnight Transit'), findsOneWidget);
      expect(find.text('Cedar Waves'), findsOneWidget);
      // Playing → pause affordance.
      expect(find.byTooltip('Pause'), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(playPauseTaps, 1);
      await tester.tap(find.byTooltip('Next'));
      await tester.pump();
      expect(nextTaps, 1);
      // Tapping the info area (not a button) opens the now-playing screen.
      await tester.tap(find.text('Midnight Transit'));
      await tester.pump();
      expect(tileTaps, 1);
      // Progress: 53s of 212s → 0.25.
      final progress = tester
          .widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      )
          .value;
      expect(progress, closeTo(0.25, 0.001));
    });

    testWidgets('paused state shows the play affordance (${_label(dark)} '
        'theme)', (tester) async {
      await pumpThemed(
        tester,
        dark: dark,
        overrides: _overrides(),
        child: MiniPlayer(
          track: _track(),
          isPlaying: false,
          position: Duration.zero,
          duration: const Duration(seconds: 212),
          onPlayPause: () {},
          onTap: () {},
        ),
      );
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      // onNext omitted → no next button at all.
      expect(find.byTooltip('Next'), findsNothing);
    });

    testWidgets('null track shows the empty state (${_label(dark)} theme)',
        (tester) async {
      await pumpThemed(
        tester,
        dark: dark,
        overrides: _overrides(),
        child: MiniPlayer(
          track: null,
          isPlaying: false,
          position: Duration.zero,
          duration: Duration.zero,
          onPlayPause: () {},
          onTap: () {},
        ),
      );
      expect(find.text('Nothing playing'), findsOneWidget);
      expect(find.byTooltip('Play'), findsOneWidget);
    });
  }
}

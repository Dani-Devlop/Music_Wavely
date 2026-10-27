/// Authored, awaiting local run (Task 2-f).
///
/// [SourceBadge] smoke test: the icon mapping per source family (local,
/// self-hosted servers, jamendo, archive, metadata-only catalogs, generic)
/// and the tooltip texts, rendered under BOTH the light and dark Wavely
/// themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/design_system/components/source_badge.dart';

import '../helpers/pump_theme.dart';

void main() {
  for (final dark in <bool>[false, true]) {
    String label(bool d) => d ? 'dark' : 'light';

    testWidgets('maps each source family to its icon (${label(dark)} '
        'theme)', (tester) async {
      Future<void> expectIcon(String sourceId, IconData icon) async {
        await pumpThemed(
          tester,
          dark: dark,
          child: SourceBadge(sourceId: sourceId),
        );
        expect(find.byIcon(icon), findsOneWidget,
            reason: 'sourceId "$sourceId" should render $icon');
      }

      await expectIcon('local', Icons.library_music_rounded);
      await expectIcon('MySubsonic', Icons.dns_rounded);
      await expectIcon('navidrome-home', Icons.dns_rounded);
      await expectIcon('jamendo', Icons.public_rounded);
      await expectIcon('archive', Icons.account_balance_rounded);
      await expectIcon('spotify', Icons.music_note_rounded);
      await expectIcon('deezer', Icons.music_note_rounded);
      await expectIcon('apple', Icons.music_note_rounded);
      await expectIcon('mystery-source', Icons.audiotrack_rounded);
    });

    testWidgets('metadata-only sources get the metadata tooltip '
        '(${label(dark)} theme)', (tester) async {
      await pumpThemed(
        tester,
        dark: dark,
        child: const SourceBadge(sourceId: 'spotify'),
      );
      expect(find.byTooltip('Metadata only'), findsOneWidget);

      await pumpThemed(
        tester,
        dark: dark,
        child: const SourceBadge(sourceId: 'archive'),
      );
      expect(find.byTooltip('Source: archive'), findsOneWidget);

      // withTooltip: false drops the tooltip entirely.
      await pumpThemed(
        tester,
        dark: dark,
        child: const SourceBadge(
          sourceId: 'spotify',
          withTooltip: false,
        ),
      );
      expect(find.byTooltip('Metadata only'), findsNothing);
    });
  }
}

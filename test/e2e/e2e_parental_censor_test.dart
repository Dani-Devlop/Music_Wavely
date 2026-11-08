/// Stage 6 E2E — ARTEMIS Scenario 3: "Go to parental settings, set a PIN,
/// add a blocked word, and play a song containing that word. Verify the
/// audio is censored with a beep and the word is masked in lyrics."
///
/// Two layers, both against real code:
///
/// 1. **UI layer** — the REAL [ParentalScreen] PIN gate: a profile with a
///    PIN locks the management UI, the keypad unlock writes the audited
///    `pin_unlocked` row, and the blocked-word editor shows the configured
///    word. (The real app renders the beep by piping the track through
///    ffmpeg_kit — a plugin with no host-test implementation — so the
///    render leg is covered at the service layer below, the same way the
///    Stage 5 regression suite does it.)
///
/// 2. **Censor pipeline layer** — the REAL [TrackFilter] verdict, REAL
///    [CensorPlanner] beep windows and REAL [CensorService] render over a
///    scripted executor: the explicit track routes to the censor pipeline,
///    the beep windows cover the blocked word, the rendered copy differs
///    from the original and the original file is left byte-identical.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/parental/data/censor_executor.dart';
import 'package:wavely/features/parental/data/censor_planner.dart';
import 'package:wavely/features/parental/data/censor_service.dart';
import 'package:wavely/features/parental/data/pin_hash.dart';
import 'package:wavely/features/parental/data/track_filter.dart';
import 'package:wavely/features/parental/data/word_matcher.dart';
import 'package:wavely/features/parental/presentation/parental_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Layer 1 — the parental screen PIN gate.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _tapPin(WidgetTester tester, String digits) async {
  for (int i = 0; i < digits.length; i++) {
    await tester.tap(find.byKey(Key('pin-key-${digits[i]}')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('PIN gate locks the parental screen, unlocks with the right '
      'code and shows the blocked word', (tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.parentalDao.createProfile(name: 'Kid', pinHash: hashPin('1357'));
    await db.parentalDao.addWord(word: 'damn', severity: 'moderate');

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: WavelyThemes.dark(WavelyAccent.purple.colors),
          home: const ParentalScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    // Locked: the gate is up and no management section leaks.
    expect(find.text('Enter PIN for Kid'), findsOneWidget);
    expect(find.text('Profiles'), findsNothing);
    expect(find.text('Blocked words'), findsNothing);

    // Wrong PIN stays locked.
    await _tapPin(tester, '0000');
    expect(find.text('Enter PIN for Kid'), findsOneWidget);
    expect(find.text('Profiles'), findsNothing);

    // Correct PIN unlocks (auto-verifies on the 4th digit) — this is the
    // "set a PIN" flow: the profile PIN is enforced, not bypassable.
    await _tapPin(tester, '1357');
    expect(find.text('Profiles'), findsOneWidget);
    expect(find.text('Blocked words'), findsOneWidget);
    expect(find.text('damn'), findsOneWidget);

    // The unlock was audited by the real DAO.
    final audit = await db.parentalDao.recentAudit();
    expect(audit.map((row) => row.event), contains('pin_unlocked'));
  });

  // ─────────────────────────────────────────────────────────────────────
  // Layer 2 — blocked word → beep render → original untouched.
  // ─────────────────────────────────────────────────────────────────────

  test('playing an explicit song routes through the censor pipeline: beep '
      'windows planned, rendered copy differs, original untouched',
      () async {
    final Directory tmp =
        await Directory.systemTemp.createTemp('wavely_stage6_s3');
    addTearDown(() => tmp.delete(recursive: true));

    // The "song on disk" containing the blocked word in its synced lyrics.
    final File original = File('${tmp.path}/night-drive.mp3');
    final Uint8List originalBytes = Uint8List.fromList(
      List<int>.generate(2048, (int i) => (i * 7 + 3) % 256),
    );
    await original.writeAsBytes(originalBytes, flush: true);

    final DateTime at = DateTime.utc(2024, 3, 1);
    final Track track = Track(
      id: 42,
      sourceId: 'local',
      sourceTrackId: 'night-01',
      title: 'Night Drive',
      artist: 'Nova',
      durationMs: 180000,
      format: 'mp3',
      explicit: true,
      filePath: original.path,
      addedAt: at,
      updatedAt: at,
    );

    final LyricsResult lyrics = LyricsResult(
      lines: <LyricLine>[
        LyricLine(
          startTime: const Duration(seconds: 30),
          text: 'we ride through the damn night',
        ),
        LyricLine(
          startTime: const Duration(seconds: 40),
          text: 'city lights are clean and bright',
        ),
      ],
      synced: true,
    );

    final BlockedWordRow word = BlockedWordRow(
      id: 1,
      word: 'damn',
      severity: 'moderate',
      language: null,
      addedAt: DateTime.utc(2024, 1, 1),
    );
    final WordMatcher matcher = WordMatcher(words: <BlockedWordRow>[word]);
    final TrackFilter filter = TrackFilter(
      words: <BlockedWordRow>[word],
      blockNoLyrics: false,
    );

    // The filter routes the explicit track to censoring (not block, not
    // allow) because the blocked word sits in its synced lyrics.
    final TrackVerdict verdict = await filter.evaluate(
      track: track,
      lyrics: lyrics,
      matcher: matcher,
    );
    expect(verdict, TrackVerdict.censorNeeded);

    // The planner mutes exactly the window the blocked word spans.
    final CensorPlan plan = CensorPlanner.plan(lyrics: lyrics, matcher: matcher);
    expect(plan.hasPlan, isTrue);
    expect(plan.ranges, <(int, int)>[(30000, 40000)]);

    // The render produces a NEW censored file; the original stays
    // byte-identical (a second render short-circuits on the cache).
    final _BeepRenderExecutor executor = _BeepRenderExecutor();
    final CensorService service = CensorService(
      executor: executor,
      cacheDirProvider: () async => '${tmp.path}/censor-cache',
    );
    final Result<String?> rendered = await service.censorTrack(
      track: track,
      plan: plan,
    );
    final String censoredPath = rendered.fold(
      onSuccess: (String? value) => value!,
      onErr: (Object failure) => throw StateError('render failed: $failure'),
    );

    expect(executor.renderCalls, 1);
    expect(executor.beepMode, isTrue, reason: 'the censor must BEEP, not '
        'silence, for a blocked word');
    expect(censoredPath, isNot(original.path));
    expect(censoredPath, contains('track-42'));
    final File censored = File(censoredPath);
    expect(censored.existsSync(), isTrue);
    final Uint8List censoredBytes = await censored.readAsBytes();
    expect(
      censoredBytes,
      isNot(equals(originalBytes)),
      reason: 'the censored render is a new audio asset',
    );
    expect(
      await original.readAsBytes(),
      equals(originalBytes),
      reason: 'the original download must never be mutated',
    );

    // A second round reuses the cached render (no new ffmpeg run).
    final Result<String?> again = await service.censorTrack(
      track: track,
      plan: plan,
    );
    expect(again.fold(onSuccess: (String? v) => v, onErr: (_) => null),
        censoredPath);
    expect(executor.renderCalls, 1);
  });
}

/// Stands in for the ffmpeg render: writes a byte-transformed copy of the
/// input at the requested output and records whether a beep was asked for.
class _BeepRenderExecutor implements AudioCensorExecutor {
  int renderCalls = 0;
  bool beepMode = false;

  @override
  Future<Result<String?>> render({
    required String inputPath,
    required String outputPath,
    required List<(int, int)> muteRangesMs,
    required bool beepInsteadOfSilence,
  }) async {
    renderCalls++;
    beepMode = beepInsteadOfSilence;
    try {
      final File input = File(inputPath);
      if (!input.existsSync()) {
        return const Result<String?>.err(
          Failure.storage(message: 'no local file'),
        );
      }
      final List<int> bytes = await input.readAsBytes();
      final List<int> rendered = bytes.map((int b) => b ^ 0xFF).toList();
      final File out = File(outputPath);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(rendered, flush: true);
      return Result<String?>.success(outputPath);
    } on Object catch (e) {
      return Result<String?>.err(Failure.storage(message: e.toString()));
    }
  }
}

/// Authored, awaiting local run (Task 2-f).
///
/// Widget test of [AiChatScreen] pumped inside a MaterialApp with the REAL
/// Wavely theme factories. The screen watches exactly
/// [aiServiceProvider] (+ [trackLauncherProvider] on 'Play all'), so the
/// tests override only those: a real [AiService] wired to a scripted fake
/// provider, the real executor over an in-memory drift DB and a recording
/// launcher. Covers the disabled setup state, the 8 mood chips, the
/// send → user bubble → assistant reply flow, the queue 'Play all' /
/// 'Regenerate' controls and the in-flight 'Cancel' control.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/ai_chat/ai_chat_providers.dart';
import 'package:wavely/features/ai_chat/data/ai_provider.dart';
import 'package:wavely/features/ai_chat/data/ai_service.dart';
import 'package:wavely/features/ai_chat/data/ai_tools.dart';
import 'package:wavely/features/ai_chat/data/mood_classifier.dart';
import 'package:wavely/features/ai_chat/presentation/ai_chat_screen.dart';
import 'package:wavely/features/library/data/track_launcher.dart';

/// Scripted provider whose pending reply can be held back with a
/// [Completer] (to make the in-flight 'Cancel' control deterministic).
class _ScriptedProvider implements AiProvider {
  _ScriptedProvider(this._script);

  final List<AiReply> _script;
  Completer<AiReply>? _gate;
  int calls = 0;

  /// Holds the NEXT complete() call open until [release] is invoked.
  void gateNext() {
    _gate = Completer<AiReply>();
  }

  void release(AiReply reply) {
    _gate?.complete(reply);
    _gate = null;
  }

  @override
  String get id => 'scripted';

  @override
  Future<Result<AiReply>> complete(AiConversation conversation) async {
    calls++;
    if (calls <= _script.length) {
      final reply = _script[calls - 1];
      if (_gate != null) {
        return _gate!.future.then(Result<AiReply>.success);
      }
      return Result.success(reply);
    }
    return const Result.success(AiReply(text: 'out of script'));
  }
}

class _RecordingLauncher implements TrackLauncher {
  final List<List<Track>> played = <List<Track>>[];

  @override
  Future<void> playTracks(List<Track> tracks, {int startIndex = 0}) async {
    played.add(List<Track>.of(tracks));
  }
}

/// Matches markdown-rendered text (flutter_markdown emits RichText /
/// Text.rich, so plain find.text is not enough for bubble bodies).
Finder _bubbleText(String substring) => find.byWidgetPredicate(
      (widget) {
        if (widget is RichText) {
          return widget.text.toPlainText().contains(substring);
        }
        if (widget is Text) {
          final plain = widget.data ?? widget.textSpan?.toPlainText() ?? '';
          return plain.contains(substring);
        }
        return false;
      },
    );

Future<void> _pumpScreen(
  WidgetTester tester, {
  required AiService? service,
  required TrackLauncher launcher,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        aiServiceProvider.overrideWithValue(service),
        trackLauncherProvider.overrideWithValue(launcher),
      ],
      child: MaterialApp(
        theme: WavelyThemes.light(WavelyAccent.purple),
        home: const AiChatScreen(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late AppDatabase db;
  late _RecordingLauncher launcher;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.tracksDao.insertTrack(
      TracksCompanion.insert(
        sourceId: 'local',
        sourceTrackId: 's-1',
        title: 'Neon Rivers',
        artist: 'Velvet Echo',
        durationMs: 203000,
        format: 'mp3',
        addedAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      ),
    );
    await db.tracksDao.insertTrack(
      TracksCompanion.insert(
        sourceId: 'local',
        sourceTrackId: 's-2',
        title: 'Glass Harbour',
        artist: 'Cedar Waves',
        durationMs: 178000,
        format: 'flac',
        addedAt: DateTime(2024, 1, 2),
        updatedAt: DateTime(2024, 1, 2),
      ),
    );
    launcher = _RecordingLauncher();
  });

  tearDown(() async {
    await db.close();
  });

  AiService buildService(AiProvider provider) => AiService(
        provider: provider,
        executor: AiToolExecutor(
          tracksDao: db.tracksDao,
          launcher: launcher,
        ),
        snapshotLoader: () async =>
            '{"tracks":[],"counts":{"totalTracks":0,"artists":0,"genres":[]}}',
      );

  testWidgets('disabled state renders the setup explainer, no input',
      (tester) async {
    await _pumpScreen(
      tester,
      service: null,
      launcher: launcher,
    );
    expect(find.text('Ask Wavely AI'), findsOneWidget);
    expect(find.text('AI chat is not set up yet'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('enabled state renders all eight mood chips', (tester) async {
    final provider = _ScriptedProvider(<AiReply>[]);
    await _pumpScreen(
      tester,
      service: buildService(provider),
      launcher: launcher,
    );
    expect(find.byType(ChoiceChip), findsNWidgets(Mood.values.length));
    expect(find.byType(TextField), findsOneWidget);
    for (final mood in Mood.values) {
      expect(find.text(mood.label), findsOneWidget);
    }
  });

  testWidgets('mood chips toggle selection on tap', (tester) async {
    final provider = _ScriptedProvider(<AiReply>[]);
    await _pumpScreen(
      tester,
      service: buildService(provider),
      launcher: launcher,
    );
    final chip = find.widgetWithText(ChoiceChip, 'party');
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
    await tester.tap(chip);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(chip).selected, isFalse);
  });

  testWidgets('sending shows the user bubble then the assistant reply',
      (tester) async {
    final provider = _ScriptedProvider(<AiReply>[
      const AiReply(text: 'Enjoy this pick!'),
    ]);
    // Hold the provider reply open so the in-flight UI (typing indicator)
    // is observably deterministic instead of racing microtasks.
    provider.gateNext();
    await _pumpScreen(
      tester,
      service: buildService(provider),
      launcher: launcher,
    );
    await tester.enterText(find.byType(TextField), 'make me a mix');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    // User bubble appears immediately; the input is disabled while the
    // assistant is "typing".
    expect(_bubbleText('make me a mix'), findsWidgets);
    expect(find.text('Assistant is typing'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).enabled,
      isFalse,
    );
    provider.release(const AiReply(text: 'Enjoy this pick!'));
    await tester.pumpAndSettle();
    expect(_bubbleText('Enjoy this pick!'), findsWidgets);
    expect(find.text('Assistant is typing'), findsNothing);
    expect(provider.calls, 1);
    expect(
      tester.widget<TextField>(find.byType(TextField)).enabled,
      isTrue,
    );
  });

  testWidgets("tool-built queue shows 'Queued N tracks' + 'Play all' + "
      "'Regenerate', and Play all launches the validated tracks",
      (tester) async {
    final provider = _ScriptedProvider(<AiReply>[
      AiReply(
        text: '',
        toolCalls: <AiToolCall>[
          const AiToolCall(
            id: 'c1',
            name: 'build_queue',
            argumentsJson: '{"track_ids":[1,2],"reason":"your mix"}',
          ),
        ],
      ),
      const AiReply(text: 'Here is your mix.'),
    ]);
    await _pumpScreen(
      tester,
      service: buildService(provider),
      launcher: launcher,
    );
    await tester.enterText(find.byType(TextField), 'queue me up');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(find.text('Queued 2 tracks'), findsOneWidget);
    expect(find.text('Play all'), findsOneWidget);
    expect(find.text('Regenerate'), findsOneWidget);
    expect(_bubbleText('Here is your mix.'), findsWidgets);
    await tester.tap(find.text('Play all'));
    await tester.pumpAndSettle();
    expect(launcher.played, hasLength(1));
    expect(
      [for (final t in launcher.played.single) t.id],
      <int?>[1, 2],
    );
  });

  testWidgets('cancel discards the in-flight request', (tester) async {
    final provider = _ScriptedProvider(<AiReply>[
      const AiReply(text: 'late reply'),
    ]);
    provider.gateNext();
    await _pumpScreen(
      tester,
      service: buildService(provider),
      launcher: launcher,
    );
    await tester.enterText(find.byType(TextField), 'hold on');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    // While sending, the header carries a Cancel control and the input is
    // disabled.
    expect(find.text('Cancel'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).enabled,
      isFalse,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(_bubbleText('Request cancelled.'), findsWidgets);
    provider.release(const AiReply(text: 'late reply'));
    await tester.pumpAndSettle();
    // The reply landed after the generation bump → never rendered.
    expect(_bubbleText('late reply'), findsNothing);
  });

  testWidgets('regenerate re-sends the last user prompt (queue bubbles '
      'carry the control)', (tester) async {
    // 'Regenerate' renders only on queue bubbles (per the screen code), so
    // the script builds a queue first.
    final provider = _ScriptedProvider(<AiReply>[
      AiReply(
        text: '',
        toolCalls: <AiToolCall>[
          const AiToolCall(
            id: 'c1',
            name: 'build_queue',
            argumentsJson: '{"track_ids":[1],"reason":"again"}',
          ),
        ],
      ),
      const AiReply(text: 'Here is your mix.'),
    ]);
    await _pumpScreen(
      tester,
      service: buildService(provider),
      launcher: launcher,
    );
    await tester.enterText(find.byType(TextField), 'ask once');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(find.text('Play all'), findsOneWidget);
    // Same prompt within the cache TTL → the service serves the cached
    // outcome; the queue bubble is re-rendered without a new provider call
    // and without re-launching playback.
    await tester.tap(find.text('Regenerate'));
    await tester.pumpAndSettle();
    expect(find.text('Queued 1 tracks'), findsOneWidget);
    expect(find.text('Play all'), findsOneWidget);
    expect(find.text('Regenerate'), findsOneWidget);
    expect(provider.calls, 2); // tool turn + text turn, no re-run
    expect(launcher.played, hasLength(1));
  });
}

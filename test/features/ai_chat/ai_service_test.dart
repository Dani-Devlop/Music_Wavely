/// Authored, awaiting local run (Task 2-f).
///
/// [AiService] orchestration tests with a scripted fake [AiProvider], the
/// REAL [AiToolExecutor] over an in-memory drift database and a recording
/// launcher: tool-call loop termination with parsed args, fabricated-id
/// rejection (only executor-validated ids ever reach playback), maxTurns
/// cap, the 10/min sliding-window rate limit with an injectable clock, the
/// 5-minute prompt cache, mood-constrained system prompts and the disabled
/// provider path.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/ai_chat/data/ai_provider.dart';
import 'package:wavely/features/ai_chat/data/ai_service.dart';
import 'package:wavely/features/ai_chat/data/ai_tools.dart';
import 'package:wavely/features/ai_chat/data/mood_classifier.dart';
import 'package:wavely/features/library/data/track_launcher.dart';

/// Scripted [AiProvider]: pops one [AiReply] per call (falling back to a
/// plain-text answer) while recording the system prompt and a snapshot of
/// the messages each turn carried.
class _ScriptedProvider implements AiProvider {
  _ScriptedProvider(this._script, {this.fallbackToolCall = false});

  final List<AiReply> _script;

  /// When the script is exhausted: `true` keeps answering with a (never
  /// resolving) tool call so the loop can only exit via maxTurns; `false`
  /// answers with plain text so the loop terminates normally.
  final bool fallbackToolCall;
  int calls = 0;
  final List<int> messageCounts = <int>[];
  final List<List<AiMessage>> messageSnapshots = <List<AiMessage>>[];
  final List<String> systemPrompts = <String>[];

  @override
  String get id => 'scripted';

  @override
  Future<Result<AiReply>> complete(AiConversation conversation) async {
    systemPrompts.add(conversation.systemPrompt);
    messageCounts.add(conversation.messages.length);
    messageSnapshots.add(<AiMessage>[
      for (final m in conversation.messages)
        AiMessage(
          role: m.role,
          content: m.content,
          toolCallJson: m.toolCallJson,
        ),
    ]);
    calls++;
    if (calls <= _script.length) {
      return Result.success(_script[calls - 1]);
    }
    if (fallbackToolCall) {
      return Result.success(
        AiReply(
          text: '',
          toolCalls: <AiToolCall>[
            _call('search_library', <String, Object?>{'query': 'ghost'}),
          ],
        ),
      );
    }
    return const Result.success(AiReply(text: 'out of script'));
  }
}

class _FailingProvider implements AiProvider {
  int calls = 0;

  @override
  String get id => 'failing';

  @override
  Future<Result<AiReply>> complete(AiConversation conversation) async {
    calls++;
    return const Result.err(Failure.network(message: 'upstream is down'));
  }
}

class _RecordingLauncher implements TrackLauncher {
  final List<List<Track>> played = <List<Track>>[];

  @override
  Future<void> playTracks(List<Track> tracks, {int startIndex = 0}) async {
    played.add(List<Track>.of(tracks));
  }
}

/// Auto-advancing fake clock: every [now] call steps [step] forward; tests
/// may also [jump] explicitly.
class _FakeClock {
  _FakeClock({DateTime? start, this.step = const Duration(seconds: 1)})
      : _t = start ?? DateTime(2024, 6, 1, 12);

  DateTime _t;
  Duration step;

  DateTime now() {
    _t = _t.add(step);
    return _t;
  }

  void jump(Duration d) => _t = _t.add(d);
}

AiToolCall _call(String name, Map<String, Object?> args) => AiToolCall(
      id: 'call-${args.hashCode}',
      name: name,
      argumentsJson: jsonEncode(args),
    );

Future<AppDatabase> _seedDb() async {
  final db = AppDatabase(NativeDatabase.memory());
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
  return db;
}

const String _snapshot =
    '{"tracks":[{"t":"Neon Rivers","id":1}],"counts":{"totalTracks":1}}';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = await _seedDb();
  });

  tearDown(() async {
    await db.close();
  });

  AiService buildService({
    required AiProvider? provider,
    TrackLauncher? launcher,
    DateTime Function()? now,
    int maxTurns = 4,
  }) {
    final toolExecutor = AiToolExecutor(
      tracksDao: db.tracksDao,
      launcher: launcher ?? _RecordingLauncher(),
    );
    return AiService(
      provider: provider,
      executor: toolExecutor,
      snapshotLoader: () async => _snapshot,
      maxTurns: maxTurns,
      now: now,
    );
  }

  group('AiService.send', () {
    test('null provider → friendly disabled error, snapshot untouched',
        () async {
      var snapshotReads = 0;
      final service = AiService(
        provider: null,
        executor: AiToolExecutor(
          tracksDao: db.tracksDao,
          launcher: _RecordingLauncher(),
        ),
        snapshotLoader: () async {
          snapshotReads++;
          return _snapshot;
        },
      );
      final result = await service.send('hello');
      result.fold(
        onErr: (f) => expect(f.message, aiDisabledMessage),
        onSuccess: (_) => fail('expected the disabled error'),
      );
      expect(snapshotReads, 0);
    });

    test('tool loop terminates and the executor sees parsed args', () async {
      final provider = _ScriptedProvider(<AiReply>[
        AiReply(
          text: 'Looking that up.',
          toolCalls: <AiToolCall>[
            _call('search_library', <String, Object?>{'query': 'neon'}),
          ],
        ),
        const AiReply(text: 'Done — found it.'),
      ]);
      final service = buildService(provider: provider);
      final result = await service.send('find neon');
      final outcome = result.fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (o) => o,
      );
      // Transcript: the in-flight text, the tool summary line, then the
      // final assistant text (line-level order per the real loop).
      expect(
        outcome.transcriptLines,
        <String>[
          'Looking that up.',
          'Found 1 matches for "neon".',
          'Done — found it.',
        ],
      );
      expect(outcome.queueBuilt, isNull);
      // Loop: turn 1 carries just the user message; turn 2 carries
      // user + assistant(toolCall) + tool(resultJson) = 3.
      expect(provider.calls, 2);
      expect(provider.messageCounts, <int>[1, 3]);
      final assistant = provider.messageSnapshots[1][1];
      expect(assistant.role, AiMessageRole.assistant);
      expect(
        AiMessage.decodeToolCall(assistant.toolCallJson)!.name,
        'search_library',
      );
      final tool = provider.messageSnapshots[1][2];
      expect(tool.role, AiMessageRole.tool);
      expect(tool.content, contains('Neon Rivers'));
      expect(tool.content, contains('"id":1'));
    });

    test('FABRICATED ids are rejected before playback ever happens',
        () async {
      final launcher = _RecordingLauncher();
      final provider = _ScriptedProvider(<AiReply>[
        AiReply(
          text: '',
          toolCalls: <AiToolCall>[
            _call(
              'build_queue',
              <String, Object?>{'track_ids': <Object?>[1, 999]},
            ),
          ],
        ),
        const AiReply(text: 'enjoy!'),
      ]);
      final service = buildService(provider: provider, launcher: launcher);
      final result = await service.send('queue something');
      final outcome = result.fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (o) => o,
      );
      // The executor (TracksDao.byIds) is where the "only ids returned by
      // tools" rule is enforced: the whole call fails, nothing is queued.
      expect(
        outcome.transcriptLines.join('\n'),
        contains('Unknown track ids: [999]'),
      );
      expect(outcome.queueBuilt, isNull);
      expect(launcher.played, isEmpty);
      // The failure travels back to the model as an error tool message.
      final tool = provider.messageSnapshots[1][2];
      expect(
        jsonDecode(tool.content),
        <String, Object?>{'error': 'Unknown track ids: [999]'},
      );
    });

    test('validated ids reach the queue with a QueueBuildSummary',
        () async {
      final launcher = _RecordingLauncher();
      final provider = _ScriptedProvider(<AiReply>[
        AiReply(
          text: '',
          toolCalls: <AiToolCall>[
            _call(
              'build_queue',
              <String, Object?>{
                'track_ids': <Object?>[2, 1],
                'reason': 'golden hour',
              },
            ),
          ],
        ),
        const AiReply(text: 'playing your mix.'),
      ]);
      final service = buildService(provider: provider, launcher: launcher);
      final outcome = (await service.send('build me a mix')).fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (o) => o,
      );
      final queue = outcome.queueBuilt!;
      expect(queue.queued, 2);
      expect(queue.trackIds, <int>[1, 2]); // re-resolved, db order
      expect(queue.reason, 'golden hour');
      expect(
        [for (final t in queue.tracks) t.id],
        <int?>[1, 2],
      );
      expect(launcher.played, hasLength(1));
    });

    test('maxTurns caps provider calls at the configured limit', () async {
      // fallbackToolCall: the provider keeps demanding a search_library
      // call, so the loop can only exit through the maxTurns guard.
      final provider = _ScriptedProvider(
        <AiReply>[],
        fallbackToolCall: true,
      );
      final service = buildService(provider: provider, maxTurns: 3);
      final outcome = (await service.send('loop forever')).fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (o) => o,
      );
      expect(provider.calls, 3);
      // Each turn executed the search (0 hits) and logged its summary.
      expect(
        outcome.transcriptLines,
        everyElement('Found 0 matches for "ghost".'),
      );
      expect(outcome.transcriptLines, hasLength(3));
    });

    test('rate limit: 10 sends/min ok, the 11th is rejected', () async {
      final clock = _FakeClock();
      final provider = _ScriptedProvider(<AiReply>[]);
      final service = buildService(provider: provider, now: clock.now);
      for (var i = 0; i < 10; i++) {
        final result = await service.send('request number $i');
        final reason = result.fold(
          onErr: (f) => f.message,
          onSuccess: (_) => '',
        );
        expect(result.isSuccess, isTrue, reason: 'send $i: $reason');
      }
      final eleventh = await service.send('request number 10');
      eleventh.fold(
        onErr: (f) => expect(
          f.message,
          'Too many AI requests — wait a moment and try again.',
        ),
        onSuccess: (_) => fail('the 11th send must be rate limited'),
      );
      expect(provider.calls, 10);
      // Sliding window: after a minute of silence the next send passes.
      clock.jump(const Duration(seconds: 61));
      final afterWindow = await service.send('request number 11');
      expect(afterWindow.isSuccess, isTrue);
      expect(provider.calls, 11);
    });

    test('identical prompt within the TTL is served from the cache',
        () async {
      final clock = _FakeClock();
      final provider = _ScriptedProvider(<AiReply>[
        const AiReply(text: 'cached answer'),
      ]);
      final service = buildService(provider: provider, now: clock.now);
      final first = (await service.send('same prompt')).fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (o) => o,
      );
      final second = (await service.send('same prompt')).fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (o) => o,
      );
      expect(identical(first, second), isTrue);
      expect(provider.calls, 1);
      // After the 5-minute TTL the provider is consulted again.
      clock.jump(const Duration(minutes: 6));
      final third = (await service.send('same prompt')).fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (o) => o,
      );
      expect(identical(first, third), isFalse);
      expect(provider.calls, 2);
    });

    test('the mood changes the cache key and reaches the system prompt',
        () async {
      final clock = _FakeClock();
      final provider = _ScriptedProvider(<AiReply>[
        const AiReply(text: 'a'),
        const AiReply(text: 'b'),
      ]);
      final service = buildService(provider: provider, now: clock.now);
      await service.send('music please');
      final heartbreak =
          MoodClassifier.classify('she left me, I am devastated');
      await service.send('music please', mood: heartbreak);
      expect(provider.calls, 2);
      final prompt = provider.systemPrompts[1];
      expect(prompt, contains('User mood: heartbreak'));
      expect(prompt, contains('exclude genres: romantic, love'));
      expect(
        prompt,
        contains(
          'Prefer tags: uplifting, empowerment, growth, discipline',
        ),
      );
      expect(prompt, contains('Restrict languages to: en'));
    });

    test('system prompt embeds the snapshot and the tools contract',
        () async {
      final provider = _ScriptedProvider(<AiReply>[
        const AiReply(text: 'ok'),
      ]);
      final service = buildService(provider: provider);
      await service.send('anything');
      final prompt = provider.systemPrompts.single;
      expect(prompt, contains(_snapshot));
      expect(prompt, contains('search_library'));
      expect(prompt, contains('never invent'));
    });

    test('provider failures surface as friendly errors, uncached',
        () async {
      final provider = _FailingProvider();
      final service = buildService(provider: provider);
      final first = await service.send('hello');
      first.fold(
        onErr: (f) => expect(f.message, contains('could not be reached')),
        onSuccess: (_) => fail('expected the network failure'),
      );
      // Failure was NOT cached → the retry really hits the provider.
      final second = await service.send('hello');
      expect(second.isErr, isTrue);
      expect(provider.calls, 2);
    });
  });
}

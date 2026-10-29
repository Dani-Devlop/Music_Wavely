/// Authored, awaiting local run (Task 2-f).
///
/// [AiToolExecutor] + `aiToolDeclarations` contract tests against a real
/// in-memory drift database: every tool schema carries the documented
/// Gemini-format shape, and the executor mapping returns ONLY ids resolved
/// through the DAO — fabricated ids are rejected with no launcher call.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/ai_chat/data/ai_provider.dart';
import 'package:wavely/features/ai_chat/data/ai_tools.dart';
import 'package:wavely/features/library/data/track_launcher.dart';

class _RecordingLauncher implements TrackLauncher {
  final List<List<Track>> played = <List<Track>>[];

  @override
  Future<void> playTracks(List<Track> tracks, {int startIndex = 0}) async {
    played.add(List<Track>.of(tracks));
  }
}

/// Builds the executor over a fresh memory DB with two seeded tracks:
/// id 1 'Neon Rivers', id 2 'Glass Harbour' (both indexed by tracks_fts).
Future<(AppDatabase, AiToolExecutor, _RecordingLauncher)>
    _makeExecutor() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.tracksDao.insertTrack(
    TracksCompanion.insert(
      sourceId: 'local',
      sourceTrackId: 'a-1',
      title: 'Neon Rivers',
      artist: 'Velvet Echo',
      album: const Value('Rivers'),
      durationMs: 203000,
      format: 'mp3',
      addedAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    ),
  );
  await db.tracksDao.insertTrack(
    TracksCompanion.insert(
      sourceId: 'local',
      sourceTrackId: 'a-2',
      title: 'Glass Harbour',
      artist: 'Cedar Waves',
      durationMs: 178000,
      format: 'flac',
      addedAt: DateTime(2024, 1, 2),
      updatedAt: DateTime(2024, 1, 2),
    ),
  );
  final launcher = _RecordingLauncher();
  final executor = AiToolExecutor(
    tracksDao: db.tracksDao,
    launcher: launcher,
  );
  return (db, executor, launcher);
}

void main() {
  group('tool schemas (aiToolDeclarations)', () {
    test('declares the four documented tools in order', () {
      expect(
        [for (final d in aiToolDeclarations) d['name']],
        <String>[
          'search_library',
          'build_queue',
          'create_playlist',
          'get_listening_stats',
        ],
      );
      expect(aiToolNames, hasLength(aiToolDeclarations.length));
    });

    test('every declaration has name, description and OBJECT parameters',
        () {
      for (final declaration in aiToolDeclarations) {
        expect(declaration['name'], isA<String>());
        expect((declaration['name'] as String).isNotEmpty, isTrue);
        expect(declaration['description'], isA<String>());
        expect(
          (declaration['description'] as String).isNotEmpty,
          isTrue,
        );
        final parameters = declaration['parameters'] as Map<String, Object>;
        expect(parameters['type'], 'OBJECT');
        // NOTE: isA<T>() is a factory — the parens are mandatory; passing
        // the bare closure would compare against the closure itself.
        expect(parameters['properties'], isA<Map<String, Object>>());
        expect((parameters['properties'] as Map).isNotEmpty, isTrue);
        expect(parameters['required'], isA<List<String>>());
      }
    });

    test('build_queue requires INTEGER track_ids (plus optional reason)',
        () {
      final buildQueue = aiToolDeclarations
          .firstWhere((d) => d['name'] == 'build_queue');
      final parameters = buildQueue['parameters'] as Map<String, Object>;
      expect(parameters['required'], <String>['track_ids']);
      final trackIds =
          (parameters['properties'] as Map<String, Object>)['track_ids']
              as Map<String, Object>;
      expect(trackIds['type'], 'ARRAY');
      expect((trackIds['items'] as Map<String, Object>)['type'], 'INTEGER');
      final reason =
          (parameters['properties'] as Map<String, Object>)['reason']
              as Map<String, Object>;
      expect(reason['type'], 'STRING');
    });
  });

  group('AiToolExecutor', () {
    test('search_library returns ONLY id/title/artist per match', () async {
      final (db, executor, _) = await _makeExecutor();
      addTearDown(db.close);
      final result = await executor.execute(
        const AiToolCall(
          id: 't1',
          name: 'search_library',
          argumentsJson: '{"query":"neon"}',
        ),
      );
      final outcome = result.fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (o) => o,
      );
      expect(outcome.toolName, 'search_library');
      final decoded = jsonDecode(outcome.resultJson) as Map<String, Object?>;
      final matches = decoded['matches'] as List<Object?>;
      expect(matches, hasLength(1));
      final match = matches.first as Map<String, Object?>;
      // Executor contract: matches carry ids + plain metadata only — no
      // file paths, cover paths, source ids or timestamps.
      expect(match.keys.toSet(), <String>{'id', 'title', 'artist'});
      expect(match['id'], 1);
      expect(match['title'], 'Neon Rivers');
      expect(match['artist'], 'Velvet Echo');
      expect(outcome.summary, 'Found 1 matches for "neon".');
    });

    test('search_library with blank query fails', () async {
      final (db, executor, _) = await _makeExecutor();
      addTearDown(db.close);
      final result = await executor.execute(
        const AiToolCall(
          id: 't2',
          name: 'search_library',
          argumentsJson: '{"query":"   "}',
        ),
      );
      result.fold(
        onErr: (f) => expect(f.message, contains('requires a query')),
        onSuccess: (_) => fail('expected failure'),
      );
    });

    test('search_library with no hits reports zero matches', () async {
      final (db, executor, _) = await _makeExecutor();
      addTearDown(db.close);
      final outcome = (await executor.execute(
        const AiToolCall(
          id: 't3',
          name: 'search_library',
          argumentsJson: '{"query":"zzzznothing"}',
        ),
      ))
          .fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (o) => o,
      );
      final decoded = jsonDecode(outcome.resultJson) as Map<String, Object?>;
      expect(decoded['matches'], isEmpty);
      expect(outcome.summary, contains('Found 0 matches'));
    });

    test('build_queue validates ids and returns the queue summary without '
        'launching', () async {
      final (db, executor, launcher) = await _makeExecutor();
      addTearDown(db.close);
      final result = await executor.execute(
        const AiToolCall(
          id: 't4',
          name: 'build_queue',
          argumentsJson: '{"track_ids":[1,2],"reason":"rainy mix"}',
        ),
      );
      final outcome = result.fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (o) => o,
      );
      expect(outcome.builtQueue, isTrue);
      expect(outcome.queueReason, 'rainy mix');
      expect(
        [for (final t in outcome.queuedTracks) t.id],
        <int?>[1, 2],
      );
      expect(outcome.resultJson,
          '{"queued":2,"reason":"rainy mix"}');
      // ARCHITECTURE: tool execution NEVER launches playback — the chat
      // bubble's 'Play all' button is the single user-initiated launch
      // point. Auto-launching here made every AI mix play twice.
      expect(launcher.played, isEmpty);
    });

    test('build_queue REJECTS fabricated ids with no launcher call',
        () async {
      final (db, executor, launcher) = await _makeExecutor();
      addTearDown(db.close);
      final result = await executor.execute(
        const AiToolCall(
          id: 't5',
          name: 'build_queue',
          argumentsJson: '{"track_ids":[1,999]}',
        ),
      );
      result.fold(
        onErr: (f) {
          // Whole call rejected — never a partial queue.
          expect(f.message, 'Unknown track ids: [999]');
        },
        onSuccess: (_) => fail('fabricated ids must fail'),
      );
      expect(launcher.played, isEmpty);
    });

    test('build_queue rejects empty / non-numeric track_ids', () async {
      final (db, executor, launcher) = await _makeExecutor();
      addTearDown(db.close);
      for (final args in <String>['{}', '{"track_ids":[]}',
          '{"track_ids":["one"]}']) {
        final result = await executor.execute(
          AiToolCall(
            id: 't6',
            name: 'build_queue',
            argumentsJson: args,
          ),
        );
        result.fold(
          onErr: (f) => expect(
            f.message,
            'build_queue requires non-empty track_ids',
            reason: 'args: $args',
          ),
          onSuccess: (_) => fail('expected failure for $args'),
        );
      }
      expect(launcher.played, isEmpty);
    });

    test('create_playlist without the bridge reports it honestly',
        () async {
      final (db, executor, _) = await _makeExecutor();
      addTearDown(db.close);
      final result = await executor.execute(
        const AiToolCall(
          id: 't7',
          name: 'create_playlist',
          argumentsJson: '{"name":"Mix","track_ids":[1]}',
        ),
      );
      result.fold(
        onErr: (f) =>
            expect(f.message, contains('playlists feature')),
        onSuccess: (_) => fail('expected honest unavailability'),
      );
    });

    test('create_playlist with the bridge validates ids then calls it',
        () async {
      final (db, executor, launcher) = await _makeExecutor();
      addTearDown(db.close);
      final calls = <(String, List<int>)>[];
      final hooked = AiToolExecutor(
        tracksDao: db.tracksDao,
        launcher: launcher,
        createPlaylist: (name, ids) async => calls.add((name, ids)),
      );
      final outcome = (await hooked.execute(
        const AiToolCall(
          id: 't8',
          name: 'create_playlist',
          argumentsJson: '{"name":"Mix","track_ids":[2,1]}',
        ),
      ))
          .fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (o) => o,
      );
      // Records use == on their FIELDS, and Dart List == is identity —
      // comparing whole records against a fresh literal can never pass.
      // Assert the fields instead.
      expect(calls, hasLength(1));
      expect(calls.single.$1, 'Mix');
      expect(calls.single.$2, <int>[2, 1]);
      final decoded = jsonDecode(outcome.resultJson) as Map<String, Object?>;
      expect(decoded['created'], 'Mix');
      expect(decoded['trackCount'], 2);
    });

    test('create_playlist rejects fabricated ids without calling the hook',
        () async {
      final (db, executor, launcher) = await _makeExecutor();
      addTearDown(db.close);
      var hookCalls = 0;
      final hooked = AiToolExecutor(
        tracksDao: db.tracksDao,
        launcher: launcher,
        createPlaylist: (name, ids) async => hookCalls++,
      );
      final result = await hooked.execute(
        const AiToolCall(
          id: 't9',
          name: 'create_playlist',
          argumentsJson: '{"name":"Mix","track_ids":[777]}',
        ),
      );
      result.fold(
        onErr: (f) =>
            expect(f.message, 'Unknown track ids: [777]'),
        onSuccess: (_) => fail('expected failure'),
      );
      expect(hookCalls, 0);
    });

    test('get_listening_stats without the bridge says stats unavailable',
        () async {
      final (db, executor, _) = await _makeExecutor();
      addTearDown(db.close);
      final outcome = (await executor.execute(
        const AiToolCall(
          id: 't10',
          name: 'get_listening_stats',
          argumentsJson: '{"period":"week"}',
        ),
      ))
          .fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (o) => o,
      );
      expect(outcome.resultJson, '{"stats":"unavailable"}');
    });

    test('get_listening_stats forwards the period to the bridge',
        () async {
      final (db, executor, launcher) = await _makeExecutor();
      addTearDown(db.close);
      final periods = <String>[];
      final hooked = AiToolExecutor(
        tracksDao: db.tracksDao,
        launcher: launcher,
        listeningStatsFallback: (period) async {
          periods.add(period);
          return '{"stats":"ok"}';
        },
      );
      final outcome = (await hooked.execute(
        const AiToolCall(
          id: 't11',
          name: 'get_listening_stats',
          argumentsJson: '{"period":"month"}',
        ),
      ))
          .fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (o) => o,
      );
      expect(periods, <String>['month']);
      expect(outcome.resultJson, '{"stats":"ok"}');
      expect(outcome.summary, 'Listening stats for month ready.');
    });

    test('get_listening_stats falls back when the bridge returns null',
        () async {
      final (db, executor, launcher) = await _makeExecutor();
      addTearDown(db.close);
      final hooked = AiToolExecutor(
        tracksDao: db.tracksDao,
        launcher: launcher,
        listeningStatsFallback: (period) async => null,
      );
      final outcome = (await hooked.execute(
        const AiToolCall(
          id: 't12',
          name: 'get_listening_stats',
          argumentsJson: '{"period":"week"}',
        ),
      ))
          .fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (o) => o,
      );
      expect(outcome.resultJson,
          '{"stats":"unavailable","period":"week"}');
    });

    test('unknown tool names fail with a typed error', () async {
      final (db, executor, _) = await _makeExecutor();
      addTearDown(db.close);
      final result = await executor.execute(
        const AiToolCall(
          id: 't13',
          name: 'hack_library',
          argumentsJson: '{}',
        ),
      );
      result.fold(
        onErr: (f) => expect(f.message, 'Unknown tool: hack_library'),
        onSuccess: (_) => fail('unknown tool must fail'),
      );
    });
  });
}

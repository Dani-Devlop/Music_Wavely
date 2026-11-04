// Stage 5 cross-feature regression — Scenario 4: AI Chat × Advanced
// Shuffle.
//
// The AI asks for a mood-based queue while a STRICT language filter is
// active in the Advanced Shuffle config. Contract under test:
//
//   MoodClassifier (deterministic keyword scoring)
//     → mood rules mapped onto ShuffleConfig (blockedGenres +
//       allowedLanguages)
//       → AdvancedShuffle filters the AI-built queue
//         → nothing outside the filter survives (except the deliberately
//           anchored current track, whose playback must never be
//           interrupted by its own shuffle config).
//
// The AI side additionally keeps its security contract: fabricated track
// ids fail the WHOLE build_queue call.
library;

import 'package:drift/native.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/mappers/track_mapper.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/ai_chat/data/ai_provider.dart';
import 'package:wavely/features/ai_chat/data/ai_tools.dart';
import 'package:wavely/features/ai_chat/data/mood_classifier.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/shuffle/advanced_shuffle.dart';

import '../support/fake_playback_engine.dart';
import '../support/track_factory.dart';

/// Never launches playback — records calls so the test can prove the AI
/// tool layer does not auto-launch either.
class _RecordingLauncher implements TrackLauncher {
  int calls = 0;

  @override
  Future<void> playTracks(List<Track> tracks, {int startIndex = 0}) async {
    calls++;
  }
}

/// Library rows for the pool: two English rock tracks, an English
/// romantic-genre track, an English love-genre track and a Spanish track.
Future<void> _seedPool(AppDatabase db) async {
  final List<Track> pool = <Track>[
    seedTrack(1,
        title: 'Stone Heart',
        artist: 'The Grit',
        genre: 'rock',
        language: 'en'),
    seedTrack(2,
        title: 'Rise Again',
        artist: 'The Grit',
        genre: 'rock',
        language: 'en'),
    seedTrack(3,
        title: 'Only You Tonight',
        artist: 'Velvet Trio',
        genre: 'romantic',
        language: 'en'),
    seedTrack(4,
        title: 'Hold Me Closer',
        artist: 'Velvet Trio',
        genre: 'love',
        language: 'en'),
    seedTrack(5,
        title: 'Bailando Sola',
        artist: 'Luna',
        genre: 'pop',
        language: 'es'),
  ];
  for (final Track t in pool) {
    await db.tracksDao.insertTrack(TrackMapper.toCompanion(t));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('MoodClassifier → ShuffleConfig mapping', () {
    test('heartbreak mood maps to the spec filter (genres + English only)',
        () {
      final MoodResult mood = MoodClassifier.classify(
        'I just went through a breakup and I am heartbroken, left me devastated',
      );
      expect(mood.mood, Mood.heartbreak);
      expect(mood.excludedGenres, <String>['romantic', 'love']);
      expect(mood.languages, <String>['en']);

      final ShuffleConfig config = ShuffleConfig(
        blockedGenres: mood.excludedGenres.toSet(),
        allowedLanguages: mood.languages.toSet(),
        seed: 42,
      );
      expect(config.blockedGenres, <String>{'romantic', 'love'});
      expect(config.allowedLanguages, <String>{'en'});
    });

    test('non-heartbreak moods carry no language restriction', () {
      final MoodResult mood =
          MoodClassifier.classify('some chill lo-fi to relax to');
      expect(mood.mood, Mood.chill);
      expect(mood.languages, isEmpty);
      expect(mood.excludedGenres, isEmpty);
      final ShuffleConfig config = ShuffleConfig(
        blockedGenres: mood.excludedGenres.toSet(),
        allowedLanguages: mood.languages.toSet(),
        seed: 7,
      );
      expect(config.allowedLanguages, isEmpty);
    });
  });

  group('AI queue through the strict shuffle filter', () {
    test('mood-filtered shuffle keeps only filtered tracks after the anchor',
        () async {
      await _seedPool(db);
      final List<Track> pool = <Track>[
        seedTrack(1,
            title: 'Stone Heart',
            artist: 'The Grit',
            genre: 'rock',
            language: 'en'),
        seedTrack(2,
            title: 'Rise Again',
            artist: 'The Grit',
            genre: 'rock',
            language: 'en'),
        seedTrack(3,
            title: 'Only You Tonight',
            artist: 'Velvet Trio',
            genre: 'romantic',
            language: 'en'),
        seedTrack(4,
            title: 'Hold Me Closer',
            artist: 'Velvet Trio',
            genre: 'love',
            language: 'en'),
        seedTrack(5,
            title: 'Bailando Sola',
            artist: 'Luna',
            genre: 'pop',
            language: 'es'),
      ];

      final MoodResult mood = MoodClassifier.classify(
        'heartbroken after the breakup',
      );
      final ShuffleConfig config = ShuffleConfig(
        blockedGenres: mood.excludedGenres.toSet(),
        allowedLanguages: mood.languages.toSet(),
        seed: 42,
      );

      // The CURRENT track is the Spanish one — playing content the filter
      // would exclude. Playback must never be interrupted by its own
      // shuffle: the anchor stays first.
      final List<Track> shuffled = const AdvancedShuffle().shuffle(
        pool,
        currentIndex: 4,
        config: config,
      );

      expect(shuffled.first.sourceTrackId, 'seed-5',
          reason: 'the anchored current track always stays first');
      final List<String> rest = <String>[
        for (final Track t in shuffled.skip(1)) t.sourceTrackId,
      ];
      expect(rest, containsAll(<String>['seed-1', 'seed-2']));
      expect(rest, isNot(contains('seed-3')),
          reason: 'romantic genre excluded by the heartbreak rule');
      expect(rest, isNot(contains('seed-4')),
          reason: 'love genre excluded by the heartbreak rule');
      expect(rest, isNot(contains('seed-5')));
      for (final Track t in shuffled.skip(1)) {
        expect(t.language, 'en',
            reason: 'the strict English filter must hold for every queued '
                'track after the anchor');
      }
      expect(shuffled, hasLength(3));
    });

    test('AI build_queue output respects the filter after shuffle mapping',
        () async {
      await _seedPool(db);
      final _RecordingLauncher launcher = _RecordingLauncher();
      final AiToolExecutor executor = AiToolExecutor(
        tracksDao: db.tracksDao,
        launcher: launcher,
      );

      // The model "queues" every library track — including the romantic and
      // Spanish ones. Validation only: ids must exist.
      final Result<AiToolOutcome> built = await executor.execute(
        AiToolCall(
          id: 'call-1',
          name: 'build_queue',
          argumentsJson:
              '{"track_ids": [1, 2, 3, 4, 5], "reason": "heartbreak mix"}',
        ),
      );
      final AiToolOutcome outcome = built.getOrElse((Failure f) => throw
          StateError('build_queue must succeed for real ids: $f'));
      expect(outcome.builtQueue, isTrue);
      expect(outcome.queuedTracks, hasLength(5));
      expect(launcher.calls, 0,
          reason: 'build_queue validates only; playback is user-initiated');

      // The orchestrator then applies the mood rules as shuffle filters.
      final MoodResult mood =
          MoodClassifier.classify('breakup, totally heartbroken');
      final ShuffleConfig config = ShuffleConfig(
        blockedGenres: mood.excludedGenres.toSet(),
        allowedLanguages: mood.languages.toSet(),
        seed: 42,
      );
      final List<Track> filtered = const AdvancedShuffle().shuffle(
        outcome.queuedTracks,
        config: config,
      );
      expect(filtered.map((Track t) => t.id).toSet(), <int>{1, 2},
          reason: 'the AI suggestion list shrinks to the filter — romantic, '
              'love and non-English tracks never reach the queue');
    });

    test('fabricated ids fail the whole AI call (security contract intact)',
        () async {
      await _seedPool(db);
      final AiToolExecutor executor = AiToolExecutor(
        tracksDao: db.tracksDao,
        launcher: _RecordingLauncher(),
      );

      final Result<AiToolOutcome> built = await executor.execute(
        AiToolCall(
          id: 'call-2',
          name: 'build_queue',
          argumentsJson: '{"track_ids": [1, 999]}',
        ),
      );
      expect(built.isErr, isTrue);
      built.fold(
        onSuccess: (_) => fail('fabricated ids must reject the whole call'),
        onErr: (Failure f) => expect(f.toString(), contains('999')),
      );
    });

    test('no-signal mood text yields no filter (empty config keeps pool)',
        () async {
      await _seedPool(db);
      final MoodResult mood =
          MoodClassifier.classify('play something nice please');
      expect(mood.mood, isNull);

      final ShuffleConfig config = ShuffleConfig(seed: 42);
      final List<Track> pool = <Track>[
        seedTrack(1,
            title: 'Stone Heart',
            artist: 'The Grit',
            genre: 'rock',
            language: 'en'),
        seedTrack(5,
            title: 'Bailando Sola',
            artist: 'Luna',
            genre: 'pop',
            language: 'es'),
      ];
      final List<Track> shuffled =
          const AdvancedShuffle().shuffle(pool, config: config);
      expect(shuffled, hasLength(2),
          reason: 'without a mood signal nothing is filtered');
    });
  });

  group('shuffle × engine boundary', () {
    test('the filtered queue loads into the engine and playback stays alive',
        () async {
      await _seedPool(db);
      final FakePlaybackEngine engine = FakePlaybackEngine();
      MoodClassifier.classify('uplifting motivation please');
      final ShuffleConfig config = ShuffleConfig(
        allowedGenres: <String>{'rock'},
        seed: 42,
      );
      final List<Track> pool = <Track>[
        seedTrack(1,
            title: 'Stone Heart',
            artist: 'The Grit',
            genre: 'rock',
            language: 'en'),
        seedTrack(2,
            title: 'Rise Again',
            artist: 'The Grit',
            genre: 'rock',
            language: 'en'),
        seedTrack(5,
            title: 'Bailando Sola',
            artist: 'Luna',
            genre: 'pop',
            language: 'es'),
      ];
      final List<Track> queue =
          const AdvancedShuffle().shuffle(pool, config: config);
      expect(queue.map((Track t) => t.id).toSet(), <int>{1, 2});

      await engine.setQueue(queue);
      await engine.play();
      engine.emitState(PlaybackState.playing);
      engine.emitPosition(const Duration(seconds: 4));
      await engine.seek(const Duration(seconds: 10));

      expect(engine.setQueueCalls, 1);
      expect(engine.lastSetQueue.map((Track t) => t.id).toSet(), <int>{1, 2});
      expect(engine.playCalls, 1);
      expect(engine.state, PlaybackState.playing);
      // The fake's seek() lands the simulated position at the seek target.
      expect(engine.position, const Duration(seconds: 10));
      expect(engine.seeks.single, const Duration(seconds: 10));
    });
  });
}

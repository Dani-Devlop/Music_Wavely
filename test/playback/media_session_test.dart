// Phase 9.1 / 9.4 — WavelyAudioHandler (mobile media session).
//
// Covers the lock-screen contract: full media item (title/artist/album/
// art/lyrics-extras), queue publication, seekbar state (position/buffered/
// speed), the control strip per playback state, the transport callbacks
// wired from QueueManager (skip next/previous, toggle), and the headset
// FF/RW rules (seekBy clamping).

import 'package:audio_service/audio_service.dart' as asv;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/engines/mobile_playback_engine.dart';
import 'package:wavely/playback/engines/playback_engine.dart';

Track _track({
  String id = 't1',
  String title = 'Song A',
  String artist = 'Artist A',
  String? album = 'Album A',
  String? coverPath = '/tmp/cover.png',
  int durationMs = 180000,
}) =>
    Track(
      sourceId: Track.localSourceId,
      sourceTrackId: id,
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      format: 'mp3',
      filePath: '/tmp/$id.mp3',
      coverPath: coverPath,
      addedAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

void main() {
  group('WavelyAudioHandler', () {
    test('syncTrack publishes the full media item (lock screen surface)', () {
      final handler = WavelyAudioHandler();
      final track = _track();
      handler.syncTrack(track, lyrics: '[00:01.00] line', queue: [track]);

      final item = handler.mediaItem.value;
      expect(item, isNotNull);
      expect(item!.title, 'Song A');
      expect(item.artist, 'Artist A');
      expect(item.album, 'Album A');
      expect(item.duration, const Duration(milliseconds: 180000));
      expect(item.artUri, Uri.file('/tmp/cover.png'));
      // Lyrics ride the extras map for lock screen / Android Auto surfaces.
      expect(item.extras?['lyrics'], '[00:01.00] line');

      // The queue becomes the Android Auto browse list.
      final queue = handler.queue.value;
      expect(queue, hasLength(1));
      expect(queue.first.title, 'Song A');
    });

    test('syncTrack(null) clears the media item', () {
      final handler = WavelyAudioHandler();
      handler.syncTrack(_track());
      handler.syncTrack(null);
      expect(handler.mediaItem.value, isNull);
    });

    test('syncState(playing) exposes the full control strip + seekbar', () {
      final handler = WavelyAudioHandler();
      handler.syncState(
        PlaybackState.playing,
        position: const Duration(seconds: 42),
        duration: const Duration(seconds: 180),
      );

      final state = handler.playbackState.value;
      expect(state.playing, isTrue);
      expect(state.processingState, asv.AudioProcessingState.ready);
      expect(state.updatePosition, const Duration(seconds: 42));
      expect(state.speed, 1.0);
      // Musicolet-parity strip: previous | pause | next.
      final actions = state.controls.map((c) => c.action).toList();
      expect(actions, contains(asv.MediaAction.pause));
      expect(actions, contains(asv.MediaAction.skipToNext));
      expect(actions, contains(asv.MediaAction.skipToPrevious));
      // Seekbar + press-and-hold seek on the lock screen.
      expect(state.systemActions, contains(asv.MediaAction.seek));
      expect(state.systemActions, contains(asv.MediaAction.seekForward));
      expect(state.systemActions, contains(asv.MediaAction.seekBackward));
    });

    test('syncState(paused) swaps the primary control to play', () {
      final handler = WavelyAudioHandler();
      handler.syncState(
        PlaybackState.paused,
        position: Duration.zero,
        duration: const Duration(seconds: 100),
      );
      final state = handler.playbackState.value;
      expect(state.playing, isFalse);
      expect(state.speed, 0.0);
      expect(
        state.controls.map((c) => c.action),
        contains(asv.MediaAction.play),
      );
      // Buffered position tracks the full duration so the seekbar renders.
      expect(state.bufferedPosition, const Duration(seconds: 100));
    });

    test('transport callbacks are forwarded (skip next/previous)', () async {
      var nextCalls = 0;
      var previousCalls = 0;
      var toggleCalls = 0;
      final handler = WavelyAudioHandler(
        onTogglePlayPause: () => toggleCalls++,
      );
      handler.setQueueCallbacks(
        onNext: () => nextCalls++,
        onPrevious: () => previousCalls++,
      );

      await handler.skipToNext();
      await handler.skipToPrevious();
      await handler.play();
      await handler.pause();
      expect(nextCalls, 1);
      expect(previousCalls, 1);
      expect(toggleCalls, 0);
    });

    test('click routes media→toggle, next→skip, previous→skip', () async {
      var toggleCalls = 0;
      var nextCalls = 0;
      var previousCalls = 0;
      final handler = WavelyAudioHandler(
        onTogglePlayPause: () => toggleCalls++,
      );
      handler.setQueueCallbacks(
        onNext: () => nextCalls++,
        onPrevious: () => previousCalls++,
      );

      await handler.click(asv.MediaButton.media);
      await handler.click(asv.MediaButton.next);
      await handler.click(asv.MediaButton.previous);
      expect(toggleCalls, 1);
      expect(nextCalls, 1);
      expect(previousCalls, 1);
    });

    test('seekBy honours the +10s/-10s FF/RW step with clamping', () async {
      final seeks = <Duration>[];
      final handler = WavelyAudioHandler(
        onSeek: (p) async => seeks.add(p),
      );

      // Mid-track forward: 30s + 10s.
      handler.syncState(
        PlaybackState.playing,
        position: const Duration(seconds: 30),
        duration: const Duration(seconds: 180),
      );
      await handler.seekForward(true);
      expect(seeks.single, const Duration(seconds: 40));

      // Discrete rewind near zero clamps to 0.
      handler.syncState(
        PlaybackState.paused,
        position: const Duration(seconds: 3),
        duration: const Duration(seconds: 180),
      );
      await handler.rewind();
      expect(seeks.last, Duration.zero);

      // Forward beyond the end clamps to the duration.
      handler.syncState(
        PlaybackState.playing,
        position: const Duration(seconds: 175),
        duration: const Duration(seconds: 180),
      );
      await handler.fastForward();
      expect(seeks.last, const Duration(seconds: 180));
    });
  });
}

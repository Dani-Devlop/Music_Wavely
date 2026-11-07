/// Tests for the Phase 7.2/8.2 pure FFmpeg command builders.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/audio_cutter/data/cutter_commands.dart';
import 'package:wavely/features/audio_cutter/data/cutter_math.dart';

void main() {
  final CutSelection selection = CutSelection(
    start: const Duration(minutes: 1, seconds: 2, milliseconds: 340),
    end: const Duration(minutes: 1, seconds: 12, milliseconds: 340),
  );

  group('buildWaveformPcmArgs / toFile', () {
    test('decodes mono 16-bit s16le at the fixed sample rate', () {
      final List<String> args = buildWaveformPcmArgs('/music/song.mp3');
      expect(args, containsAll(<String>['-ac', '1', '-ar', '8000']));
      expect(args.contains('-vn'), isTrue);
      final int fIndex = args.indexOf('-f');
      expect(args[fIndex + 1], 's16le');
    });

    test('file variant writes PCM to the given path', () {
      final List<String> args = buildWaveformPcmToFileArgs(
        inputPath: '/music/song.mp3',
        pcmFile: '/tmp/out.pcm',
      );
      expect(args, contains('/tmp/out.pcm'));
      expect(args, containsAll(<String>['-f', 's16le']));
    });
  });

  group('buildCutArgs', () {
    test('seeks input-side and limits duration', () {
      final List<String> args = buildCutArgs(
        inputPath: '/music/song.mp3',
        outputPath: '/music/song (cut).m4a',
        selection: selection,
      );
      final int ssIndex = args.indexOf('-ss');
      expect(args[ssIndex + 1], '01:02.340');
      final int tIndex = args.indexOf('-t');
      expect(args[tIndex + 1], '00:10.000');
      expect(args.contains('/music/song.mp3'), isTrue);
      expect(args.contains('/music/song (cut).m4a'), isTrue);
    });

    test('picks the codec from the output extension', () {
      expect(
        audioCodecForExtension('/a/b.mp3'),
        'libmp3lame',
      );
      expect(audioCodecForExtension('/a/b.flac'), 'flac');
      expect(audioCodecForExtension('/a/b.wav'), 'pcm_s16le');
      expect(audioCodecForExtension('/a/b.m4a'), 'aac');
      expect(audioCodecForExtension('/a/b.unknown'), 'aac');
    });

    test('override codec wins', () {
      final List<String> args = buildCutArgs(
        inputPath: '/music/song.mp3',
        outputPath: '/tmp/ringtone.m4a',
        selection: selection,
        codec: 'aac',
      );
      final int codecIndex = args.indexOf('-c:a');
      expect(args[codecIndex + 1], 'aac');
    });

    test('ringtone variant forces AAC at 192k', () {
      final List<String> args = buildCutForRingtoneArgs(
        inputPath: '/music/song.mp3',
        outputPath: '/tmp/ringtone.m4a',
        selection: selection,
      );
      expect(args.contains('-b:a'), isTrue);
      final int bIndex = args.indexOf('-b:a');
      expect(args[bIndex + 1], '192k');
    });
  });

  group('buildEbur128Args', () {
    test('runs the ebur128 filter with peak detection', () {
      final List<String> args = buildEbur128Args('/music/song.mp3');
      final int filterIndex = args.indexOf('-filter_complex');
      expect(args[filterIndex + 1], 'ebur128=peak=true');
      expect(args, containsAll(<String>['-f', 'null', '-']));
    });
  });
}

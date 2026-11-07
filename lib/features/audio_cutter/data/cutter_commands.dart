/// Pure FFmpeg argument builders for the audio cutter (Phase 7.2).
///
/// Keeping command construction separate from execution makes every
/// command unit-testable: the controller composes args, the injected
/// [FFmpegExecutor] runs them.
library;

import 'package:wavely/core/audio/ffmpeg_executor.dart';
import 'package:wavely/features/audio_cutter/data/cutter_math.dart';

/// PCM decode used for the waveform preview: mono, 16-bit, 8 kHz — small
/// enough to keep in memory for long tracks.
const int kWaveformSampleRate = 8000;

/// Default waveform resolution.
const int kWaveformBuckets = 400;

/// Args that decode [inputPath] to little-endian s16le mono PCM for the
/// waveform preview.
List<String> buildWaveformPcmArgs(String inputPath) => <String>[
      '-hide_banner',
      '-nostdin',
      '-i',
      inputPath,
      '-vn',
      '-ac',
      '1',
      '-ar',
      '$kWaveformSampleRate',
      '-f',
      's16le',
      '-',
    ];

/// Args that cut [selection] out of [inputPath] into [outputPath].
///
/// `-ss` before `-i` seeks input-side (fast, frame-accurate for our
/// re-encode); audio is re-encoded to AAC in .m4a output or stream-copied
/// for formats that tolerate cutting at arbitrary positions? Copy cannot
/// cut at arbitrary boundaries for most codecs, so we re-encode — codec
/// chosen by extension via [audioCodecForExtension].
List<String> buildCutArgs({
  required String inputPath,
  required String outputPath,
  required CutSelection selection,
  String? codec,
}) => <String>[
      '-hide_banner',
      '-nostdin',
      '-y',
      '-ss',
      formatCutTimestampMs(selection.start),
      '-i',
      inputPath,
      '-t',
      formatCutTimestampMs(selection.length),
      '-vn',
      '-c:a',
      codec ?? audioCodecForExtension(outputPath),
      '-movflags',
      '+faststart',
      outputPath,
    ];

/// Args that cut and normalize loudness for a ringtone-sized output
/// (mono-friendly re-encode; the ringtone setter consumes the file).
List<String> buildCutForRingtoneArgs({
  required String inputPath,
  required String outputPath,
  required CutSelection selection,
}) => <String>[
      ...buildCutArgs(
        inputPath: inputPath,
        outputPath: outputPath,
        selection: selection,
        codec: 'aac',
      ),
      '-b:a',
      '192k',
    ];

/// Codec matching the output extension; defaults to AAC (m4a) which every
/// tested target accepts.
String audioCodecForExtension(String outputPath) {
  final String lower = outputPath.toLowerCase();
  if (lower.endsWith('.mp3')) {
    return 'libmp3lame';
  }
  if (lower.endsWith('.flac')) {
    return 'flac';
  }
  if (lower.endsWith('.ogg') || lower.endsWith('.opus')) {
    return 'libopus';
  }
  if (lower.endsWith('.wav')) {
    return 'pcm_s16le';
  }
  return 'aac';
}

/// Runs [executor] and returns the decoded PCM bytes printed to stdout via
/// a temp file indirection: FFmpegKit has no byte-pipe on all platforms, so
/// the caller passes a temp [pcmFile] path that this command writes to
/// (see [buildWaveformPcmToFileArgs]).
List<String> buildWaveformPcmToFileArgs({
  required String inputPath,
  required String pcmFile,
}) => <String>[
      '-hide_banner',
      '-nostdin',
      '-y',
      '-i',
      inputPath,
      '-vn',
      '-ac',
      '1',
      '-ar',
      '$kWaveformSampleRate',
      '-f',
      's16le',
      pcmFile,
    ];

/// Standard ebur128 loudness measurement command (ReplayGain scan,
/// Phase 8.2) — kept next to the cutter's command builders because both
/// are pure arg lists over [FFmpegExecutor].
List<String> buildEbur128Args(String inputPath) => <String>[
      '-hide_banner',
      '-nostdin',
      '-i',
      inputPath,
      '-filter_complex',
      'ebur128=peak=true',
      '-f',
      'null',
      '-',
    ];

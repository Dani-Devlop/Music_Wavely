/// State + controller for the audio cutter (Phase 7.2).
///
/// Pipeline: decode → waveform peaks → user drags selection → cut via
/// FFmpeg → optional "set as ringtone / notification / alarm". All
/// command/timestamp math lives in pure functions (see `cutter_math.dart`
/// / `cutter_commands.dart`); this controller orchestrates them through an
/// injected [FFmpegExecutor].
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wavely/core/audio/ffmpeg_executor.dart';
import 'package:wavely/features/audio_cutter/data/cutter_commands.dart';
import 'package:wavely/features/audio_cutter/data/cutter_math.dart';
import 'package:wavely/features/audio_cutter/data/ringtone_saver.dart';
import 'package:wavely/features/audio_cutter/data/waveform_peaks.dart';

/// Where the cutter is in its pipeline.
enum CutterPhase {
  idle,
  decodingWaveform,
  ready,
  cutting,
  savingRingtone,
  error,
}

/// Cutter screen state.
class AudioCutterState {
  const AudioCutterState({
    this.phase = CutterPhase.idle,
    this.sourcePath = '',
    this.trackLength = Duration.zero,
    this.peaks,
    this.selection,
    this.error,
    this.lastOutputPath,
    this.ringtoneResult,
  });

  final CutterPhase phase;
  final String sourcePath;
  final Duration trackLength;
  final WaveformPeaks? peaks;
  final CutSelection? selection;
  final String? error;

  /// Output of the last cut.
  final String? lastOutputPath;

  /// Result of the last ringtone save.
  final RingtoneSaveResult? ringtoneResult;

  bool get isBusy =>
      phase == CutterPhase.decodingWaveform ||
      phase == CutterPhase.cutting ||
      phase == CutterPhase.savingRingtone;

  AudioCutterState copyWith({
    CutterPhase? phase,
    String? sourcePath,
    Duration? trackLength,
    WaveformPeaks? peaks,
    CutSelection? selection,
    String? error,
    String? lastOutputPath,
    RingtoneSaveResult? ringtoneResult,
    bool clearError = false,
    bool clearRingtone = false,
  }) =>
      AudioCutterState(
        phase: phase ?? this.phase,
        sourcePath: sourcePath ?? this.sourcePath,
        trackLength: trackLength ?? this.trackLength,
        peaks: peaks ?? this.peaks,
        selection: selection ?? this.selection,
        error: clearError ? null : (error ?? this.error),
        lastOutputPath: lastOutputPath ?? this.lastOutputPath,
        ringtoneResult:
            clearRingtone ? null : (ringtoneResult ?? this.ringtoneResult),
      );
}

/// Directory resolver for temp/PCM files — injectable for tests.
typedef TempDirectoryResolver = Future<Directory> Function();

/// Default: application support directory.
Future<Directory> defaultTempDirectory() async =>
    getApplicationSupportDirectory();

/// Drives the cutter screen.
class AudioCutterController extends StateNotifier<AudioCutterState> {
  AudioCutterController({
    FFmpegExecutor? executor,
    RingtoneSaver? ringtoneSaver,
    TempDirectoryResolver? tempDir,
  })  : _executor = executor ?? const FFmpegKitExecutor(),
        _ringtoneSaver = ringtoneSaver ?? RingtoneSaver(),
        _tempDir = tempDir ?? defaultTempDirectory,
        super(const AudioCutterState());

  final FFmpegExecutor _executor;
  final RingtoneSaver _ringtoneSaver;
  final TempDirectoryResolver _tempDir;

  /// Loads [sourcePath]: probes duration via the waveform decode itself
  /// (the PCM length is authoritative at 8 kHz mono).
  Future<void> load(String sourcePath) async {
    if (!await File(sourcePath).exists()) {
      state = AudioCutterState(
        phase: CutterPhase.error,
        sourcePath: sourcePath,
        error: 'File not found: $sourcePath',
      );
      return;
    }
    state = AudioCutterState(
      phase: CutterPhase.decodingWaveform,
      sourcePath: sourcePath,
    );
    final String? pcmPath = await _writePcmToTemp(sourcePath);
    if (pcmPath == null) {
      state = state.copyWith(
        phase: CutterPhase.error,
        error: 'FFmpeg is not available on this platform — '
            'the cutter needs FFmpeg to decode audio',
      );
      return;
    }
    final Uint8List? pcm = await _readPcm(pcmPath);
    if (pcm == null || pcm.isEmpty) {
      state = state.copyWith(
        phase: CutterPhase.error,
        error: 'Could not decode audio for the waveform',
      );
      return;
    }
    final WaveformPeaks peaks = WaveformPeaks.fromPcmBytes(
      pcm,
      bucketCount: kWaveformBuckets,
      sampleRate: kWaveformSampleRate,
    );
    final Duration length =
        Duration(milliseconds: peaks.durationMs);
    state = state.copyWith(
      phase: CutterPhase.ready,
      trackLength: length,
      peaks: peaks,
      selection: clampSelection(
        Duration.zero,
        length,
        length,
      ),
    );
  }

  /// Updates the selection (UI passes raw handle positions).
  void updateSelection(Duration a, Duration b) {
    if (state.phase != CutterPhase.ready) {
      return;
    }
    state = state.copyWith(
      selection: clampSelection(a, b, state.trackLength),
    );
  }

  /// Selects the whole track.
  void selectAll() {
    if (state.phase != CutterPhase.ready) {
      return;
    }
    state = state.copyWith(
      selection: clampSelection(
        Duration.zero,
        state.trackLength,
        state.trackLength,
      ),
    );
  }

  /// Cuts the current selection into a new file next to the source
  /// (`<name> (cut).<ext>` by default, overridable via [outputPath]).
  Future<String?> cut({String? outputPath}) async {
    final CutSelection? selection = state.selection;
    if (state.phase != CutterPhase.ready ||
        selection == null ||
        !selection.isValid) {
      return null;
    }
    final String out = outputPath ?? _defaultCutPath(state.sourcePath);
    state = state.copyWith(phase: CutterPhase.cutting, clearError: true);
    final FFmpegRunResult result = await _executor.execute(
      buildCutArgs(
        inputPath: state.sourcePath,
        outputPath: out,
        selection: selection,
      ),
    );
    if (!result.success) {
      state = state.copyWith(
        phase: CutterPhase.error,
        error: 'Cut failed: ${result.logs ?? 'unknown FFmpeg error'}',
      );
      return null;
    }
    state = state.copyWith(
      phase: CutterPhase.ready,
      lastOutputPath: out,
    );
    return out;
  }

  /// Cuts and saves the selection as [kind].
  Future<RingtoneSaveResult?> saveAsRingtone(RingtoneKind kind) async {
    final CutSelection? selection = state.selection;
    if (state.phase != CutterPhase.ready ||
        selection == null ||
        !selection.isValid) {
      return null;
    }
    state = state.copyWith(
      phase: CutterPhase.savingRingtone,
      clearError: true,
      clearRingtone: true,
    );
    try {
      final Directory temp = await _tempDir();
      final String tempCut =
          '${temp.path}/wavely-ringtone-${DateTime.now().millisecondsSinceEpoch}.m4a';
      final FFmpegRunResult result = await _executor.execute(
        buildCutForRingtoneArgs(
          inputPath: state.sourcePath,
          outputPath: tempCut,
          selection: selection,
        ),
      );
      if (!result.success) {
        state = state.copyWith(
          phase: CutterPhase.error,
          error: 'Cut failed: ${result.logs ?? 'unknown FFmpeg error'}',
        );
        return null;
      }
      final RingtoneSaveResult saved =
          await _ringtoneSaver.saveAs(tempCut, kind);
      try {
        await File(tempCut).delete();
      } on Object {
        // Temp cleanup is best-effort.
      }
      state = state.copyWith(
        phase: CutterPhase.ready,
        ringtoneResult: saved,
      );
      return saved;
    } on Object catch (error) {
      state = state.copyWith(phase: CutterPhase.error, error: '$error');
      return null;
    }
  }

  /// Decodes to a temp PCM file; `null` when FFmpeg is unavailable.
  Future<String?> _writePcmToTemp(String sourcePath) async {
    try {
      final Directory temp = await _tempDir();
      final String pcmPath =
          '${temp.path}/wavely-waveform-${DateTime.now().millisecondsSinceEpoch}.pcm';
      final FFmpegRunResult result = await _executor.execute(
        buildWaveformPcmToFileArgs(
          inputPath: sourcePath,
          pcmFile: pcmPath,
        ),
      );
      if (!result.success) {
        return null;
      }
      return pcmPath;
    } on Object {
      return null;
    }
  }

  Future<Uint8List?> _readPcm(String path) async {
    try {
      final File file = File(path);
      final Uint8List bytes = await file.readAsBytes();
      try {
        await file.delete();
      } on Object {
        // Temp cleanup is best-effort.
      }
      return bytes;
    } on Object {
      return null;
    }
  }

  String _defaultCutPath(String sourcePath) {
    final String dir = p.dirname(sourcePath);
    final String name = p.basenameWithoutExtension(sourcePath);
    final String ext = p.extension(sourcePath).isEmpty
        ? '.m4a'
        : p.extension(sourcePath);
    return '$dir/$name (cut)$ext';
  }
}

/// Manual provider (one cutter screen at a time).
final audioCutterControllerProvider =
    StateNotifierProvider.autoDispose<AudioCutterController, AudioCutterState>(
  (ref) => AudioCutterController(),
);

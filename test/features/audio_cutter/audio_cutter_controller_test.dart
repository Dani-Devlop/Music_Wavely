/// Tests for the Phase 7.2 audio cutter controller (fake executor, fake
/// ringtone filesystem, real temp PCM decoding path).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/audio/ffmpeg_executor.dart';
import 'package:wavely/features/audio_cutter/data/cutter_math.dart';
import 'package:wavely/features/audio_cutter/data/ringtone_saver.dart';
import 'package:wavely/features/audio_cutter/logic/audio_cutter_controller.dart';

/// Fake executor: records commands and synthesizes PCM output for the
/// waveform decode, success for everything else.
class FakeExecutor implements FFmpegExecutor {
  FakeExecutor({this.failOn = const <String>{}});

  final List<List<String>> commands = <List<String>>[];
  final Set<String> failOn;
  bool available = true;

  @override
  bool get isAvailable => available;

  @override
  Future<FFmpegRunResult> execute(List<String> args) async {
    commands.add(List<String>.of(args));
    final bool isPcmDecode = args.contains('s16le');
    if (isPcmDecode) {
      // Write real PCM into the output path (last non-flag arg):
      // 88000 samples @8 kHz = 11 s of quiet audio.
      final String outPath = args.last;
      final ByteData pcm = ByteData(88000 * 2);
      for (var i = 0; i < 88000; i++) {
        pcm.setInt16(i * 2, 8000, Endian.little);
      }
      await File(outPath).writeAsBytes(pcm.buffer.asUint8List());
      return const FFmpegRunResult(success: true, logs: 'decoded');
    }
    if (failOn.contains('cut')) {
      return const FFmpegRunResult(success: false, logs: 'boom');
    }
    // Cut target file: the output path is the last arg, except for the
    // ringtone variant which appends the bitrate pair afterwards.
    final List<String> args2 = List<String>.of(args);
    if (args2.length >= 2 && args2[args2.length - 2] == '-b:a') {
      args2.removeRange(args2.length - 2, args2.length);
    }
    final String outPath = args2.last;
    await File(outPath).writeAsBytes(<int>[1, 2, 3]);
    return const FFmpegRunResult(success: true, logs: 'cut ok');
  }
}

/// Fake ringtone filesystem capturing copies.
class FakeRingtoneFs implements RingtoneFilesystem {
  final Map<String, String> copies = <String, String>{};

  @override
  Directory directory(String path) => Directory(path);

  @override
  Future<void> copy(String source, String destination) async {
    copies[source] = destination;
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wavely-cutter-ctrl');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Temp cleanup is best-effort.
    }
  });

  test('load decodes the waveform and enters ready with full selection',
      () async {
    final String source = '${tempDir.path}/song.mp3';
    await File(source).writeAsBytes(<int>[1, 2, 3]);
    final FakeExecutor executor = FakeExecutor();
    final AudioCutterController controller = AudioCutterController(
      executor: executor,
      tempDir: () async => tempDir,
    );
    addTearDown(controller.dispose);

    await controller.load(source);

    expect(controller.state.phase, CutterPhase.ready);
    expect(controller.state.peaks, isNotNull);
    expect(controller.state.trackLength,
        const Duration(seconds: 11));
    expect(controller.state.selection, isNotNull);
    expect(controller.state.selection!.isValid, isTrue);
    // One PCM decode command was issued.
    expect(executor.commands, hasLength(1));
    expect(executor.commands.single.contains('s16le'), isTrue);
  });

  test('load surfaces an error for missing files', () async {
    final AudioCutterController controller = AudioCutterController(
      executor: FakeExecutor(),
      tempDir: () async => tempDir,
    );
    addTearDown(controller.dispose);

    await controller.load('${tempDir.path}/nope.mp3');
    expect(controller.state.phase, CutterPhase.error);
    expect(controller.state.error, contains('File not found'));
  });

  test('updateSelection clamps through the shared math', () async {
    final String source = '${tempDir.path}/song.mp3';
    await File(source).writeAsBytes(<int>[1]);
    final AudioCutterController controller = AudioCutterController(
      executor: FakeExecutor(),
      tempDir: () async => tempDir,
    );
    addTearDown(controller.dispose);
    await controller.load(source);

    controller.updateSelection(
      const Duration(seconds: 5),
      const Duration(seconds: 1),
    );
    final CutSelection? selection = controller.state.selection;
    expect(selection!.start, const Duration(seconds: 1));
    expect(selection.end, const Duration(seconds: 5));
  });

  test('cut runs the built command and stores the output path', () async {
    final String source = '${tempDir.path}/song.mp3';
    await File(source).writeAsBytes(<int>[1]);
    final FakeExecutor executor = FakeExecutor();
    final AudioCutterController controller = AudioCutterController(
      executor: executor,
      tempDir: () async => tempDir,
    );
    addTearDown(controller.dispose);
    await controller.load(source);

    final String? output = await controller.cut();
    expect(output, isNotNull);
    expect(File(output!).existsSync(), isTrue);
    expect(controller.state.lastOutputPath, output);
    final List<String> cutCommand = executor.commands.last;
    expect(cutCommand.contains('-ss'), isTrue);
    expect(cutCommand.contains('-t'), isTrue);
  });

  test('cut failure degrades to the error phase with logs', () async {
    final String source = '${tempDir.path}/song.mp3';
    await File(source).writeAsBytes(<int>[1]);
    final AudioCutterController controller = AudioCutterController(
      executor: FakeExecutor(failOn: <String>{'cut'}),
      tempDir: () async => tempDir,
    );
    addTearDown(controller.dispose);
    await controller.load(source);

    final String? output = await controller.cut();
    expect(output, isNull);
    expect(controller.state.phase, CutterPhase.error);
    expect(controller.state.error, contains('boom'));
  });

  test('saveAsRingtone cuts to temp then hands off to the saver',
      () async {
    final String source = '${tempDir.path}/song.mp3';
    await File(source).writeAsBytes(<int>[1]);
    final FakeExecutor executor = FakeExecutor();
    final FakeRingtoneFs fs = FakeRingtoneFs();
    final AudioCutterController controller = AudioCutterController(
      executor: executor,
      ringtoneSaver: RingtoneSaver(fs: fs),
      tempDir: () async => tempDir,
    );
    addTearDown(controller.dispose);
    await controller.load(source);

    final RingtoneSaveResult? result =
        await controller.saveAsRingtone(RingtoneKind.ringtone);
    expect(result, isNotNull);
    expect(fs.copies, hasLength(1));
    // The temp cut file was cleaned up after the copy.
    final String tempCut = fs.copies.keys.single;
    expect(File(tempCut).existsSync(), isFalse);
    expect(controller.state.ringtoneResult, isNotNull);
  });
}

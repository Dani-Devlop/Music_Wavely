/// Tests for the Phase 7.1 batch tag editor controller.
///
/// Uses the REAL IO bridge over temporary files (no tag-layer mocking) so
/// the batch semantics are proven end-to-end.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/tag_editor/data/tag_io.dart';
import 'package:wavely/features/tag_editor/data/tag_io_service.dart';
import 'package:wavely/features/tag_editor/data/tag_models.dart';
import 'package:wavely/features/tag_editor/logic/tag_editor_controller.dart';
import '../../support/audio_fixtures.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wavely-tag-ctrl');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Temp cleanup is best-effort.
    }
  });

  Future<List<String>> seedFiles(int count) async {
    final List<String> paths = <String>[];
    for (var i = 0; i < count; i++) {
      final String path = '${tempDir.path}/track$i.mp3';
      await File(path).writeAsBytes(
        minimalMp3Bytes(
          textFrames: <String, String>{
            'TIT2': 'Title $i',
            'TPE1': 'Artist $i',
          },
        ),
        flush: true,
      );
      paths.add(path);
    }
    return paths;
  }

  group('single-file mode', () {
    test('loads tags and applies field edits', () async {
      final List<String> paths = await seedFiles(1);
      final TagEditorController controller = TagEditorController();
      addTearDown(controller.dispose);

      await controller.load(paths);
      expect(controller.state.entries.single.isLoaded, isTrue);
      expect(controller.state.entries.single.original!.title, 'Title 0');

      controller.updateField(TagField.title, 'Fresh Title');
      expect(
        controller.state.entries.single.current!.title,
        'Fresh Title',
      );
      expect(
        controller.state.entries.single.changes(),
        contains(TagField.title),
      );
    });

    test('save writes the current draft to disk', () async {
      final List<String> paths = await seedFiles(1);
      final TagEditorController controller = TagEditorController();
      addTearDown(controller.dispose);
      await controller.load(paths);

      controller.updateField(TagField.artist, 'Rewritten Artist');
      final BatchTagWriteResult result = await controller.save();

      expect(result.allSucceeded, isTrue);
      final EditableTags readBack = controller.state.entries.single.original!;
      expect(readBack.artist, 'Rewritten Artist');
      expect(readBack.title, 'Title 0');
    });

    test('parse-from-filenames fills title (and artist when present)',
        () async {
      final List<String> paths = await seedFiles(1);
      final TagEditorController controller = TagEditorController();
      addTearDown(controller.dispose);
      await controller.load(paths);

      controller.updateField(TagField.title, '');
      controller.parseFromFilenames(onlySelected: false);
      // File name is "track0.mp3" → title "track0".
      expect(controller.state.entries.single.current!.title, 'track0');
    });

    test('setCover marks a cover change and save embeds it', () async {
      final List<String> paths = await seedFiles(1);
      final TagEditorController controller = TagEditorController();
      addTearDown(controller.dispose);
      await controller.load(paths);

      controller.setCover(Uint8List.fromList(<int>[5, 6, 7]), 'image/png');
      expect(controller.state.entries.single.hasCoverChange, isTrue);

      final BatchTagWriteResult result = await controller.save();
      expect(result.allSucceeded, isTrue);
      expect(controller.state.entries.single.original!.coverBytes,
          hasLength(3));
    });
  });

  group('batch mode', () {
    test('checked fields apply to every file; unchecked keep values',
        () async {
      final List<String> paths = await seedFiles(2);
      final TagEditorController controller = TagEditorController();
      addTearDown(controller.dispose);
      await controller.load(paths);

      expect(controller.state.isBatch, isTrue);
      expect(controller.state.batchDraft, isNotNull);

      controller.toggleBatchField(TagField.genre);
      controller.toggleBatchField(TagField.albumArtist);
      controller.updateField(TagField.genre, 'Batched Genre');
      controller.updateField(TagField.albumArtist, 'Batched Album Artist');

      final BatchTagWriteResult result = await controller.save();
      expect(result.succeeded, hasLength(2));
      expect(result.failed, isEmpty);

      for (var i = 0; i < paths.length; i++) {
        final EditableTags tags = readTagsOf(controller, i);
        expect(tags.genre, 'Batched Genre');
        expect(tags.albumArtist, 'Batched Album Artist');
        // Unchecked fields keep their per-file values.
        expect(tags.title, 'Title $i');
        expect(tags.artist, 'Artist $i');
      }
    });

    test('batch cover replacement applies to every file', () async {
      final List<String> paths = await seedFiles(2);
      final TagEditorController controller = TagEditorController();
      addTearDown(controller.dispose);
      await controller.load(paths);

      controller.setCover(Uint8List.fromList(<int>[1, 2]), 'image/jpeg');
      final BatchTagWriteResult result = await controller.save();
      expect(result.allSucceeded, isTrue);
      expect(readTagsOf(controller, 0).coverBytes, hasLength(2));
      expect(readTagsOf(controller, 1).coverBytes, hasLength(2));
    });

    test('one unreadable file degrades to a per-file error entry',
        () async {
      final List<String> paths = await seedFiles(2);
      final String bogus = '${tempDir.path}/bogus.mp3';
      await File(bogus).writeAsBytes(<int>[1, 2, 3], flush: true);
      final TagEditorController controller = TagEditorController();
      addTearDown(controller.dispose);

      await controller.load(<String>[...paths, bogus]);
      final TagEditorEntry badEntry = controller.state.entries
          .singleWhere((TagEditorEntry entry) => entry.filePath == bogus);
      expect(badEntry.isLoaded, isFalse);
      expect(badEntry.loadError, isNotNull);

      // Batch save still processes the readable files.
      controller.toggleBatchField(TagField.genre);
      controller.updateField(TagField.genre, 'Still Works');
      final BatchTagWriteResult result = await controller.save();
      expect(result.succeeded, hasLength(2));
    });
  });

  group('selection + clamping', () {
    test('select switches the single-mode target', () async {
      final List<String> paths = await seedFiles(2);
      final TagEditorController controller = TagEditorController();
      addTearDown(controller.dispose);
      await controller.load(paths);

      controller.select(1);
      expect(controller.state.selectedIndex, 1);
      expect(
        controller.state.selected!.original!.title,
        'Title 1',
      );
    });

    test('parseFromFilenames applies to every entry in batch mode',
        () async {
      final List<String> paths = await seedFiles(2);
      final TagEditorController controller = TagEditorController();
      addTearDown(controller.dispose);
      await controller.load(paths);

      controller.parseFromFilenames();
      expect(controller.state.entries[0].current!.title, 'track0');
      expect(controller.state.entries[1].current!.title, 'track1');
    });
  });
}

EditableTags readTagsOf(TagEditorController controller, int index) {
  // Re-read through the real bridge to prove the bytes on disk. The
  // controller only refreshes `original` in single mode, so batch-mode
  // assertions read straight from the file via the production service.
  final TagEditorEntry entry = controller.state.entries[index];
  return const AudioMetadataTagIo().read(File(entry.filePath));
}

EditableTags readTagsFromPath(String path) =>
    readTagsFromFile(File(path));

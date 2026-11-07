/// Tests for the Phase 7.3 file operations (real temp filesystem).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/library/data/file_operations/file_operations.dart';

void main() {
  late Directory tempDir;
  late Directory targetDir;
  const LocalFileOperations ops = LocalFileOperations();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wavely-fileops');
    targetDir = Directory('${tempDir.path}/target');
    await targetDir.create();
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Temp cleanup is best-effort.
    }
  });

  Future<String> seedFile(String name) async {
    final String path = '${tempDir.path}/$name';
    await File(path).writeAsString('audio', flush: true);
    return path;
  }

  group('rename', () {
    test('renames within the same directory keeping the extension', () async {
      final String source = await seedFile('old name.mp3');
      final FileOpResult result = await ops.rename(source, 'new name');
      expect(result.isSuccess, isTrue);
      expect(result.targetPath, '${tempDir.path}/new name.mp3');
      expect(File(result.targetPath!).existsSync(), isTrue);
      expect(File(source).existsSync(), isFalse);
    });

    test('rejects overwriting an existing target', () async {
      final String source = await seedFile('a.mp3');
      await seedFile('b.mp3');
      final FileOpResult result = await ops.rename(source, 'b');
      expect(result.isSuccess, isFalse);
      expect(File(source).existsSync(), isTrue);
    });

    test('defuses separator injection (target stays in the directory)',
        () async {
      final String source = await seedFile('evil.mp3');
      final FileOpResult result = await ops.rename(source, '../escape');
      // The sanitizer strips the separators, so the rename succeeds but
      // the target stays inside the source directory (no traversal).
      expect(result.isSuccess, isTrue);
      expect(result.targetPath, '${tempDir.path}/..escape.mp3');
      expect(File(source).existsSync(), isFalse);
    });

    test('sanitizeFileName rules', () {
      expect(ops.sanitizeFileName('  clean name '), 'clean name');
      expect(ops.sanitizeFileName('a/b'), 'ab');
      expect(ops.sanitizeFileName('a\\b'), 'ab');
      expect(ops.sanitizeFileName('..'), isNull);
      expect(ops.sanitizeFileName('.'), isNull);
      expect(ops.sanitizeFileName('   '), isNull);
    });
  });

  group('move / copy', () {
    test('move relocates the file', () async {
      final String source = await seedFile('movable.mp3');
      final FileOpResult result = await ops.move(source, targetDir.path);
      expect(result.isSuccess, isTrue);
      expect(
        File('${targetDir.path}/movable.mp3').existsSync(),
        isTrue,
      );
      expect(File(source).existsSync(), isFalse);
    });

    test('copy keeps the source', () async {
      final String source = await seedFile('copyable.mp3');
      final FileOpResult result = await ops.copy(source, targetDir.path);
      expect(result.isSuccess, isTrue);
      expect(File(source).existsSync(), isTrue);
      expect(
        File('${targetDir.path}/copyable.mp3').existsSync(),
        isTrue,
      );
    });

    test('both fail on a missing target directory', () async {
      final String source = await seedFile('x.mp3');
      final FileOpResult moved =
          await ops.move(source, '${tempDir.path}/missing');
      final FileOpResult copied =
          await ops.copy(source, '${tempDir.path}/missing');
      expect(moved.isSuccess, isFalse);
      expect(copied.isSuccess, isFalse);
    });

    test('both refuse to clobber an existing target name', () async {
      final String source = await seedFile('dupe.mp3');
      await File('${targetDir.path}/dupe.mp3').writeAsString('existing');
      expect((await ops.move(source, targetDir.path)).isSuccess, isFalse);
      expect((await ops.copy(source, targetDir.path)).isSuccess, isFalse);
    });
  });

  group('delete', () {
    test('deletes permanently', () async {
      final String source = await seedFile('doomed.mp3');
      final FileOpResult result = await ops.delete(source);
      expect(result.isSuccess, isTrue);
      expect(File(source).existsSync(), isFalse);
    });

    test('fails for missing files', () async {
      final FileOpResult result =
          await ops.delete('${tempDir.path}/ghost.mp3');
      expect(result.isSuccess, isFalse);
    });
  });

  group('batch helpers', () {
    test('runBatch continues past failures and reports both sides',
        () async {
      final String ok = await seedFile('ok.mp3');
      final FileOpBatchResult result = await runBatch(
        ops,
        FileOpKind.delete,
        <String>[ok, '${tempDir.path}/ghost.mp3'],
      );
      expect(result.succeeded, hasLength(1));
      expect(result.failed, hasLength(1));
      expect(result.allSucceeded, isFalse);
    });

    test('renamePattern applies %n and %t placeholders uniquely', () async {
      final String a = await seedFile('alpha.mp3');
      final String b = await seedFile('beta.mp3');
      final FileOpBatchResult result =
          await renamePattern(ops, <String>[a, b], 'Wavely %n - %t');
      expect(result.allSucceeded, isTrue);
      expect(File('${tempDir.path}/Wavely 1 - alpha.mp3').existsSync(),
          isTrue);
      expect(File('${tempDir.path}/Wavely 2 - beta.mp3').existsSync(),
          isTrue);
    });

    test('renamePattern keeps the extension on single renames', () async {
      final String source = await seedFile('track.mp3');
      final FileOpBatchResult result = await runBatch(
        ops,
        FileOpKind.rename,
        <String>[source],
        newName: 'renamed track',
      );
      expect(result.allSucceeded, isTrue);
      expect(
        File('${tempDir.path}/renamed track.mp3').existsSync(),
        isTrue,
      );
    });
  });
}

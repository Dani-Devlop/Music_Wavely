import 'dart:io';

import 'package:wavely/sources/download_file_executor.dart';

/// IO-platform implementation of [DownloadFileExecutor].
class IoDownloadFileExecutor implements DownloadFileExecutor {
  @override
  Future<void> ensureDir(String dirPath) async {
    final Directory dir = Directory(dirPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  @override
  Future<void> writeFromStream(
    Stream<List<int>> bytes,
    String path, {
    int startOffset = 0,
  }) async {
    final RandomAccessFile handle =
        File(path).openSync(mode: FileMode.append);
    try {
      if (startOffset > 0) {
        handle.setPositionSync(startOffset);
      }
      await for (final List<int> chunk in bytes) {
        handle.writeFromSync(chunk);
      }
    } finally {
      await handle.close();
    }
  }

  @override
  Future<int> fileSize(String path) async => File(path).length();

  @override
  Future<bool> exists(String path) async => File(path).exists();

  @override
  Future<void> delete(String path) async {
    final File f = File(path);
    if (f.existsSync()) {
      await f.delete();
    }
  }

  @override
  Stream<List<int>> readStream(String path) => File(path).openRead();

  @override
  Future<void> writeString(String path, String contents) async {
    await File(path).writeAsString(contents, flush: true);
  }

  @override
  File fileAt(String path) => File(path);
}

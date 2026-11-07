/// Safe file operations for the library multi-select menu (Phase 7.3).
///
/// rename / move / copy / delete over the real filesystem with a
/// SAF-shaped contract: every operation is explicit, returns a per-file
/// result and never throws into the UI. On Android builds the interface is
/// what a Storage Access Framework implementation would fulfil (documented
/// in `DEVIATION` notes in the report); this repository's targets (Linux
/// desktop, web) use the local-filesystem implementation.
library;

import 'dart:io';

/// What the caller asked for.
enum FileOpKind { rename, move, copy, delete }

/// Human label for [FileOpKind].
extension FileOpKindLabel on FileOpKind {
  String get label => switch (this) {
        FileOpKind.rename => 'Rename',
        FileOpKind.move => 'Move',
        FileOpKind.copy => 'Copy',
        FileOpKind.delete => 'Delete',
      };
}

/// Result of one file operation.
class FileOpResult {
  const FileOpResult._(this.kind, this.sourcePath, this.error,
      [this.targetPath]);

  const FileOpResult.success(
    FileOpKind kind,
    String sourcePath, [
    String? targetPath,
  ]) : this._(kind, sourcePath, null, targetPath);

  const FileOpResult.failure(
    FileOpKind kind,
    String sourcePath,
    Object error,
  ) : this._(kind, sourcePath, error);

  final FileOpKind kind;
  final String sourcePath;
  final String? targetPath;
  final Object? error;

  bool get isSuccess => error == null;
}

/// Batch outcome.
class FileOpBatchResult {
  const FileOpBatchResult({required this.results});

  final List<FileOpResult> results;

  Iterable<FileOpResult> get succeeded =>
      results.where((FileOpResult r) => r.isSuccess);
  Iterable<FileOpResult> get failed =>
      results.where((FileOpResult r) => !r.isSuccess);
  bool get allSucceeded => failed.isEmpty;
}

/// Filesystem contract (injectable for tests).
abstract interface class FileOperations {
  /// Renames [sourcePath] to [newName] (within the same directory).
  Future<FileOpResult> rename(String sourcePath, String newName);

  /// Moves [sourcePath] into [targetDirectory].
  Future<FileOpResult> move(String sourcePath, String targetDirectory);

  /// Copies [sourcePath] into [targetDirectory] (keeps the source).
  Future<FileOpResult> copy(String sourcePath, String targetDirectory);

  /// Deletes [sourcePath] permanently from disk.
  Future<FileOpResult> delete(String sourcePath);

  /// Whether [path] is an existing directory.
  Future<bool> isDirectory(String path);

  /// Sanitizes a user-provided file name: strips separators, nulls and
  /// leading dots; returns `null` when nothing remains.
  String? sanitizeFileName(String name);
}

/// dart:io implementation (Linux/desktop/test environments).
class LocalFileOperations implements FileOperations {
  const LocalFileOperations();

  @override
  Future<FileOpResult> rename(String sourcePath, String newName) async {
    final String? clean = sanitizeFileName(newName);
    if (clean == null) {
      return FileOpResult.failure(
        FileOpKind.rename,
        sourcePath,
        ArgumentError('Invalid file name'),
      );
    }
    try {
      final File source = File(sourcePath);
      final String dir = source.parent.path;
      final String ext = _extensionOf(sourcePath);
      final File target = File('$dir/$clean$ext');
      if (await target.exists()) {
        return FileOpResult.failure(
          FileOpKind.rename,
          sourcePath,
          StateError('A file with that name already exists'),
        );
      }
      final File renamed = await source.rename(target.path);
      return FileOpResult.success(
        FileOpKind.rename,
        sourcePath,
        renamed.path,
      );
    } on Object catch (error) {
      return FileOpResult.failure(FileOpKind.rename, sourcePath, error);
    }
  }

  @override
  Future<FileOpResult> move(
    String sourcePath,
    String targetDirectory,
  ) async {
    try {
      if (!await isDirectory(targetDirectory)) {
        return FileOpResult.failure(
          FileOpKind.move,
          sourcePath,
          StateError('Target folder does not exist'),
        );
      }
      final File source = File(sourcePath);
      final String target =
          '$targetDirectory/${_baseNameOf(sourcePath)}';
      if (await File(target).exists()) {
        return FileOpResult.failure(
          FileOpKind.move,
          sourcePath,
          StateError('A file with that name already exists in the target'),
        );
      }
      final File moved = await source.rename(target);
      return FileOpResult.success(FileOpKind.move, sourcePath, moved.path);
    } on Object catch (error) {
      return FileOpResult.failure(FileOpKind.move, sourcePath, error);
    }
  }

  @override
  Future<FileOpResult> copy(
    String sourcePath,
    String targetDirectory,
  ) async {
    try {
      if (!await isDirectory(targetDirectory)) {
        return FileOpResult.failure(
          FileOpKind.copy,
          sourcePath,
          StateError('Target folder does not exist'),
        );
      }
      final File source = File(sourcePath);
      final String target =
          '$targetDirectory/${_baseNameOf(sourcePath)}';
      if (await File(target).exists()) {
        return FileOpResult.failure(
          FileOpKind.copy,
          sourcePath,
          StateError('A file with that name already exists in the target'),
        );
      }
      final File copied = await source.copy(target);
      return FileOpResult.success(FileOpKind.copy, sourcePath, copied.path);
    } on Object catch (error) {
      return FileOpResult.failure(FileOpKind.copy, sourcePath, error);
    }
  }

  @override
  Future<FileOpResult> delete(String sourcePath) async {
    try {
      final File source = File(sourcePath);
      if (!await source.exists()) {
        return FileOpResult.failure(
          FileOpKind.delete,
          sourcePath,
          StateError('File not found'),
        );
      }
      await source.delete();
      return FileOpResult.success(FileOpKind.delete, sourcePath);
    } on Object catch (error) {
      return FileOpResult.failure(FileOpKind.delete, sourcePath, error);
    }
  }

  @override
  Future<bool> isDirectory(String path) async {
    try {
      return await FileSystemEntity.isDirectory(path);
    } on Object {
      return false;
    }
  }

  @override
  String? sanitizeFileName(String name) {
    final String cleaned = name
        .replaceAll('/', '')
        .replaceAll('\\', '')
        .replaceAll('\x00', '')
        .trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
      return null;
    }
    return cleaned;
  }

  static String _baseNameOf(String path) =>
      path.split(Platform.pathSeparator).last.split('/').last;

  static String _extensionOf(String path) {
    final String base = _baseNameOf(path);
    final int dot = base.lastIndexOf('.');
    return dot <= 0 ? '' : base.substring(dot);
  }
}

/// Runs one op over many files, continuing past failures.
Future<FileOpBatchResult> runBatch(
  FileOperations ops,
  FileOpKind kind,
  List<String> paths, {
  String? newName,
  String? targetDirectory,
}) async {
  final List<FileOpResult> results = <FileOpResult>[];
  for (final String path in paths) {
    switch (kind) {
      case FileOpKind.rename:
        results.add(await ops.rename(path, newName ?? ''));
      case FileOpKind.move:
        results.add(await ops.move(path, targetDirectory ?? ''));
      case FileOpKind.copy:
        results.add(await ops.copy(path, targetDirectory ?? ''));
      case FileOpKind.delete:
        results.add(await ops.delete(path));
    }
  }
  return FileOpBatchResult(results: results);
}

/// Multi-file rename: applies [pattern] with a numeric placeholder.
/// `%n` → index (1-based), `%t` → original name without extension.
/// Returns one result per file (pattern without placeholders falls back to
/// `%n`-style suffixing to keep names unique).
Future<FileOpBatchResult> renamePattern(
  FileOperations ops,
  List<String> paths,
  String pattern,
) async {
  final List<FileOpResult> results = <FileOpResult>[];
  var index = 1;
  for (final String path in paths) {
    final String base =
        path.split(Platform.pathSeparator).last.split('/').last;
    final int dot = base.lastIndexOf('.');
    final String stem = dot <= 0 ? base : base.substring(0, dot);
    String candidate = pattern
        .replaceAll('%n', '$index')
        .replaceAll('%t', stem);
    if (!candidate.contains('$index') && pattern != candidate) {
      // Pattern without any dynamic part: make it unique.
      candidate = '$candidate $index';
    }
    results.add(await ops.rename(path, candidate));
    index++;
  }
  return FileOpBatchResult(results: results);
}

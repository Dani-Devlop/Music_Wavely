import 'package:wavely/domain/repositories/source_file.dart';

/// Abstracts every disk operation the download manager needs so the service
/// and the sources compile (and fail loudly) on web while doing real work on
/// io platforms.
abstract class DownloadFileExecutor {
  /// Creates [dirPath] (recursively) when missing.
  Future<void> ensureDir(String dirPath);

  /// Streams [bytes] into [path], positioning the writer at [startOffset]
  /// (used for HTTP Range resume).
  Future<void> writeFromStream(
    Stream<List<int>> bytes,
    String path, {
    int startOffset = 0,
  });

  /// Size of the file at [path] in bytes.
  Future<int> fileSize(String path);

  /// Whether a file exists at [path].
  Future<bool> exists(String path);

  /// Deletes the file at [path] when present.
  Future<void> delete(String path);

  /// Streams the file at [path] for post-download checksumming.
  Stream<List<int>> readStream(String path);

  /// Writes [contents] as UTF-8 text (provenance sidecars).
  Future<void> writeString(String path, String contents);

  /// Returns the platform [File] for [path] (SourceProvider.download
  /// contract return value).
  File fileAt(String path);
}

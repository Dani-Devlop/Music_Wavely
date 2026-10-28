import 'package:wavely/domain/repositories/source_file.dart';
import 'package:wavely/sources/download_file_executor.dart';

/// Compile-only web stub. Never functional: writing downloads to disk is an
/// io-platform capability, mirroring the Stage 1.1 `source_file_stub.dart`
/// contract.
class IoDownloadFileExecutor implements DownloadFileExecutor {
  @override
  Never ensureDir(String dirPath) => _unsupported();

  @override
  Never writeFromStream(
    Stream<List<int>> bytes,
    String path, {
    int startOffset = 0,
  }) =>
      _unsupported();

  @override
  Never fileSize(String path) => _unsupported();

  @override
  Never exists(String path) => _unsupported();

  @override
  Never delete(String path) => _unsupported();

  @override
  Never readStream(String path) => _unsupported();

  @override
  Never writeString(String path, String contents) => _unsupported();

  @override
  Never fileAt(String path) => _unsupported();

  Never _unsupported() => throw UnsupportedError(
        'Download file operations require an IO platform '
        '(desktop or mobile).',
      );
}

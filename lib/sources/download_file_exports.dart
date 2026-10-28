/// Single import point for the download file-execution seam: the
/// [DownloadFileExecutor] interface plus its conditional implementation
/// (io arm does real disk work; web arm is compile-only and throws).
export 'download_file_executor.dart';
export 'download_file_executor_stub.dart'
    if (dart.library.io) 'download_file_executor_io.dart';

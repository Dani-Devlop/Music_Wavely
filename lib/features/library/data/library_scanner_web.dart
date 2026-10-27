import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/library_scanner.dart';

/// Web stub of the library scanner.
///
/// Browser sandboxing makes recursive folder scans impossible, so picking
/// returns nothing and scanning immediately completes with an explanatory
/// error that the UI surfaces as an error state message.
class WebLibraryScanner extends LibraryScanner {
  /// Constant because the stub has no state.
  const WebLibraryScanner();

  static const String _unsupportedMessage =
      'Scanning is not supported on web yet';

  @override
  Stream<ScanEvent> scan(List<String> folders) async* {
    yield const ScanEvent.completed(
      count: 0,
      errors: <String>[_unsupportedMessage],
    );
  }

  @override
  Future<List<String>> pickFolders() async => const <String>[];

  @override
  Future<List<String>> watchFolders() async => const <String>[];
}

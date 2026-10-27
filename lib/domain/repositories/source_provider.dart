import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/source_file.dart';

/// Contract every audio source (local library, self-hosted server, free
/// catalog, ...) must fulfil.
///
/// Note: [download] returns a File resolved through a conditional export
/// (io implementation / compile-only web stub) — downloading is an
/// io-platform capability; the web arm throws if ever invoked.
abstract class SourceProvider {
  String get id;
  String get displayName;
  bool get supportsStreaming;
  bool get supportsDownload;
  bool get supportsSearch;

  Future<List<Track>> search(String q, {int limit = 20});

  Future<StreamUrl> resolveStream(Track t);

  Future<File> download(
    Track t, {
    required String targetPath,
    required AudioQuality quality,
  });

  Future<Map<String, dynamic>> getMetadata(String sourceTrackId);
}

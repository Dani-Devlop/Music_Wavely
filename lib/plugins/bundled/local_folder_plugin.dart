/// Bundled "Local Folders" plugin (Stage 4, DAP feature 2.3).
///
/// Proof of the plugin architecture: a [WavelyPlugin] that contributes a
/// real [SourceProvider] over user-chosen folders, entirely inside the
/// sandbox rules (no dynamic code, no extra privileges — it only ever
/// touches the injected [FileSystem]).
///
/// The source intentionally stays read-only (no download) and cheap: it
/// lists audio files, matches searches against file names and plays them
/// through the engines' local-path path. Deeper library management (tags,
/// covers, FTS) remains the job of the local library scanner.
library;

import 'package:file_system/file_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/plugins/plugin_api.dart';
import 'package:wavely/sources/source_exception.dart';

/// `SourceProvider.id` of the local folder plugin's source.
const String localFolderSourceId = 'local-folder';

/// Audio extensions the folder source exposes (mirrors the archive.org
/// audio set).
const Set<String> kLocalFolderAudioExtensions = <String>{
  'mp3', 'flac', 'wav', 'ogg', 'oga', 'm4a',
};

/// Hard cap on enumerated entries per scan so a huge tree can never stall
/// a search (documented in docs/DAP_FEATURES.md).
const int kMaxScanEntries = 5000;

/// The bundled local-folder plugin.
class LocalFolderPlugin implements WavelyPlugin {
  /// Creates the plugin over [folders] (absolute paths); [fs] is
  /// injectable for tests ([MemoryFileSystem]).
  LocalFolderPlugin({required List<String> folders, FileSystem? fs})
      : _folders = List<String>.of(folders),
        _fs = fs ?? LocalFileSystem();

  final List<String> _folders;
  final FileSystem _fs;
  LocalFolderSource? _source;

  @override
  PluginManifest get manifest => const PluginManifest(
        id: 'plugin.local-folder',
        name: 'Local Folders',
        version: '0.1.0',
        capabilities: <PluginCapability>[PluginCapability.source],
        description: 'Plays audio files from folders chosen by the owner.',
      );

  /// Folders this plugin watches (read-only view).
  List<String> get folders => List<String>.unmodifiable(_folders);

  /// The source contributed during [init] (null before init / after
  /// dispose).
  LocalFolderSource? get contributedSource => _source;

  @override
  Future<void> init(PluginHostContext context) async {
    _source = LocalFolderSource(folders: _folders, fs: _fs);
    context.registerSource(_source!);
  }

  @override
  Future<void> dispose() async {
    _source = null;
  }
}

/// A read-only SourceProvider over local folders.
class LocalFolderSource implements SourceProvider {
  /// Creates the source over [folders] (absolute paths); [fs] injectable
  /// for tests.
  LocalFolderSource({required List<String> folders, FileSystem? fs})
      : _folders = List<String>.of(folders),
        _fs = fs ?? LocalFileSystem();

  final List<String> _folders;
  final FileSystem _fs;

  @override
  String get id => localFolderSourceId;

  @override
  String get displayName => 'Local Folders (plugin)';

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsDownload => false;

  @override
  bool get supportsSearch => true;

  @override
  Future<List<Track>> search(String q, {int limit = 20}) async {
    final String query = q.trim().toLowerCase();
    if (query.isEmpty) {
      return const <Track>[];
    }
    final List<Track> hits = <Track>[];
    var scanned = 0;
    for (final String folder in _folders) {
      final Directory dir = _fs.directory(folder);
      if (!dir.existsSync()) {
        continue;
      }
      for (final FileSystemEntity entity
          in dir.listSync(recursive: true, followLinks: false)) {
        if (scanned >= kMaxScanEntries || hits.length >= limit) {
          return hits;
        }
        scanned++;
        if (entity is! File) {
          continue;
        }
        final String ext = _extensionOf(entity.path);
        if (!kLocalFolderAudioExtensions.contains(ext)) {
          continue;
        }
        final String base = _basenameWithoutExtension(entity.path);
        if (!base.toLowerCase().contains(query)) {
          continue;
        }
        hits.add(_trackFromFile(entity, ext));
      }
    }
    return hits;
  }

  @override
  Future<StreamUrl> resolveStream(Track t) async {
    final String? path = t.filePath;
    if (t.sourceId != localFolderSourceId || path == null || path.isEmpty) {
      throw const SourceApiException(
        'local-folder source can only resolve its own tracks',
      );
    }
    if (!_fs.file(path).existsSync()) {
      throw SourceApiException('file disappeared: $path');
    }
    // Engines treat this as a local file path (the web engine plays
    // URLs; io engines open paths directly).
    return StreamUrl(url: path);
  }

  @override
  Future<dynamic> download(
    Track t, {
    required String targetPath,
    required AudioQuality quality,
  }) async {
    throw UnsupportedError('local-folder source is read-only');
  }

  @override
  Future<Map<String, dynamic>> getMetadata(String sourceTrackId) async {
    final File file = _fs.file(sourceTrackId);
    if (!file.existsSync()) {
      throw SourceApiException('unknown local-folder track: $sourceTrackId');
    }
    final FileStat stat = file.statSync();
    return <String, dynamic>{
      'path': file.path,
      'sizeBytes': stat.size,
      'format': _extensionOf(file.path),
      'modifiedMsEpoch': stat.modified.millisecondsSinceEpoch,
    };
  }

  Track _trackFromFile(File file, String ext) {
    final String path = file.path;
    final String parent = _fs.path.basename(_fs.path.dirname(path));
    final String grandParent =
        _fs.path.basename(_fs.path.dirname(_fs.path.dirname(path)));
    final FileStat stat = file.statSync();
    return Track(
      sourceId: localFolderSourceId,
      sourceTrackId: path,
      title: _basenameWithoutExtension(path),
      artist: parent.isEmpty ? 'Unknown Artist' : parent,
      album: grandParent.isEmpty ? null : grandParent,
      durationMs: 0,
      format: ext,
      filePath: path,
      addedAt: stat.modified,
      updatedAt: stat.modified,
    );
  }

  String _extensionOf(String path) {
    final String base = _fs.path.basename(path);
    final int dot = base.lastIndexOf('.');
    if (dot <= 0 || dot >= base.length - 1) {
      return '';
    }
    return base.substring(dot + 1).toLowerCase();
  }

  String _basenameWithoutExtension(String path) {
    final String base = _fs.path.basename(path);
    final int dot = base.lastIndexOf('.');
    return dot <= 0 ? base : base.substring(0, dot);
  }
}

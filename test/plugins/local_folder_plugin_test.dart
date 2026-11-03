/// Stage 4: plugin host lifecycle + the bundled LocalFolderPlugin
/// (including the shared SourceProvider contract suite).
library;

import 'package:file_system/file_system.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/plugins/bundled/local_folder_plugin.dart';
import 'package:wavely/plugins/plugin_api.dart';
import 'package:wavely/plugins/plugin_host.dart';

import '../sources/source_contract.dart';

/// Builds an in-memory tree:
/// `/music/Aurora/Nebula Drive/01 Starfield.mp3`
/// `/music/Aurora/Nebula Drive/02 Ion Trail.flac`
/// `/music/notes.txt` (not audio)
MemoryFileSystem buildMusicFs() {
  final MemoryFileSystem fs = MemoryFileSystem();
  final Directory root = fs.directory('/music');
  root.createSync(recursive: true);
  fs
      .file('/music/Aurora/Nebula Drive/01 Starfield.mp3')
      .createSync(recursive: true);
  fs
      .file('/music/Aurora/Nebula Drive/02 Ion Trail.flac')
      .createSync(recursive: true);
  fs.file('/music/notes.txt').createSync(recursive: true);
  return fs;
}

Track folderTrack(MemoryFileSystem fs, String path) {
  final FileStat stat = fs.file(path).statSync();
  final String base = fs.path.basename(path);
  final String ext =
      base.contains('.') ? base.split('.').last.toLowerCase() : '';
  return Track(
    sourceId: localFolderSourceId,
    sourceTrackId: path,
    title: base.substring(0, base.lastIndexOf('.')),
    artist: 'Aurora',
    durationMs: 0,
    format: ext,
    filePath: path,
    addedAt: stat.modified,
    updatedAt: stat.modified,
  );
}

void main() {
  group('PluginHost', () {
    test('describeBundled lists manifests without loading plugins', () {
      final PluginHost host = PluginHost(
        factories: <WavelyPluginFactory>[
          () => LocalFolderPlugin(folders: const <String>['/music']),
        ],
      );
      final List<PluginManifest> manifests = host.describeBundled();
      expect(manifests, hasLength(1));
      expect(manifests.single.id, 'plugin.local-folder');
      expect(host.loadedManifests, isEmpty);
      expect(host.registeredSources, isEmpty);
    });

    test('loadAll init-order registers contributed sources', () async {
      final PluginHost host = PluginHost(
        factories: <WavelyPluginFactory>[
          () => LocalFolderPlugin(folders: const <String>['/music']),
        ],
      );
      final List<PluginLoadResult> results = await host.loadAll();
      expect(results, hasLength(1));
      expect(results.single.ok, isTrue);
      expect(host.loadedManifests.single.id, 'plugin.local-folder');
      expect(host.registeredSources, hasLength(1));
      expect(host.registeredSources.single.id, localFolderSourceId);
    });

    test('one failing plugin does not break the others', () async {
      final PluginHost host = PluginHost(
        factories: <WavelyPluginFactory>[
          () => LocalFolderPlugin(folders: const <String>['/music']),
          _ExplodingPlugin(),
        ],
      );
      final List<PluginLoadResult> results = await host.loadAll();
      expect(results, hasLength(2));
      expect(results[0].ok, isTrue);
      expect(results[1].ok, isFalse);
      expect(results[1].error, contains('init'));
      expect(host.loadedManifests, hasLength(1));
      expect(host.registeredSources, hasLength(1));
    });

    test('disposeAll is idempotent and drops registrations', () async {
      final PluginHost host = PluginHost(
        factories: <WavelyPluginFactory>[
          () => LocalFolderPlugin(folders: const <String>['/music']),
        ],
      );
      await host.loadAll();
      await host.disposeAll();
      expect(host.loadedManifests, isEmpty);
      expect(host.registeredSources, isEmpty);
      // Second dispose must be a no-op, not a crash.
      await host.disposeAll();
    });
  });

  group('LocalFolderPlugin', () {
    test('manifest is stable and declares only the source capability', () {
      final LocalFolderPlugin plugin = LocalFolderPlugin(
        folders: const <String>['/music'],
      );
      expect(plugin.manifest.id, 'plugin.local-folder');
      expect(plugin.manifest.name, isNotEmpty);
      expect(plugin.manifest.capabilities,
          <PluginCapability>[PluginCapability.source]);
    });

    test('init registers exactly one source; dispose unregisters', () async {
      final LocalFolderPlugin plugin = LocalFolderPlugin(
        folders: const <String>['/music'],
        fs: buildMusicFs(),
      );
      final _RecordingContext context = _RecordingContext();
      await plugin.init(context);
      expect(context.sources, hasLength(1));
      expect(plugin.contributedSource, same(context.sources.single));
      await plugin.dispose();
      expect(plugin.contributedSource, isNull);
    });
  });

  group('LocalFolderSource.search', () {
    test('finds audio files by case-insensitive name match', () async {
      final LocalFolderSource source = LocalFolderSource(
        folders: const <String>['/music'],
        fs: buildMusicFs(),
      );
      final List<Track> hits = await source.search('starfield');
      expect(hits, hasLength(1));
      expect(hits.single.title, '01 Starfield');
      expect(hits.single.artist, 'Nebula Drive');
      expect(hits.single.album, 'Aurora');
      expect(hits.single.format, 'mp3');
      expect(hits.single.sourceId, localFolderSourceId);
      expect(hits.single.sourceTrackId, isNotEmpty);
    });

    test('empty / blank queries return nothing', () async {
      final LocalFolderSource source = LocalFolderSource(
        folders: const <String>['/music'],
        fs: buildMusicFs(),
      );
      expect(await source.search(''), isEmpty);
      expect(await source.search('   '), isEmpty);
    });

    test('respects the limit and the scan cap', () async {
      final LocalFolderSource source = LocalFolderSource(
        folders: const <String>['/music'],
        fs: buildMusicFs(),
      );
      expect((await source.search('e', limit: 1)), hasLength(1));
    });

    test('missing folders are skipped silently', () async {
      final LocalFolderSource source = LocalFolderSource(
        folders: const <String>['/does-not-exist', '/music'],
        fs: buildMusicFs(),
      );
      expect(await source.search('ion trail'), hasLength(1));
    });

    test('non-audio files are ignored', () async {
      final LocalFolderSource source = LocalFolderSource(
        folders: const <String>['/music'],
        fs: buildMusicFs(),
      );
      expect(await source.search('notes'), isEmpty);
    });
  });

  group('LocalFolderSource streaming / metadata', () {
    test('resolveStream returns the local path for its own tracks',
        () async {
      final MemoryFileSystem fs = buildMusicFs();
      final LocalFolderSource source = LocalFolderSource(
        folders: const <String>['/music'],
        fs: fs,
      );
      final Track track = folderTrack(
        fs,
        '/music/Aurora/Nebula Drive/02 Ion Trail.flac',
      );
      final StreamUrl url = await source.resolveStream(track);
      expect(url.url, '/music/Aurora/Nebula Drive/02 Ion Trail.flac');
    });

    test('resolveStream refuses foreign tracks and vanished files',
        () async {
      final LocalFolderSource source = LocalFolderSource(
        folders: const <String>['/music'],
        fs: buildMusicFs(),
      );
      final Track foreign = folderTrack(
        buildMusicFs(),
        '/music/Aurora/Nebula Drive/02 Ion Trail.flac',
      ).copyWith(sourceId: 'archive');
      await expectLater(
        source.resolveStream(foreign),
        throwsA(isA<SourceApiException>()),
      );
      final Track vanished = folderTrack(
        buildMusicFs(),
        '/music/ghost.mp3',
      );
      await expectLater(
        source.resolveStream(vanished),
        throwsA(isA<SourceApiException>()),
      );
    });

    test('getMetadata returns size/format facts for known ids', () async {
      final MemoryFileSystem fs = buildMusicFs();
      final LocalFolderSource source = LocalFolderSource(
        folders: const <String>['/music'],
        fs: fs,
      );
      final Map<String, dynamic> meta =
          await source.getMetadata('/music/Aurora/Nebula Drive/01 Starfield.mp3');
      expect(meta['path'], '/music/Aurora/Nebula Drive/01 Starfield.mp3');
      expect(meta['format'], 'mp3');
      expect(meta['sizeBytes'], isA<int>());
    });

    test('getMetadata throws for unknown ids', () async {
      final LocalFolderSource source = LocalFolderSource(
        folders: const <String>['/music'],
        fs: buildMusicFs(),
      );
      await expectLater(
        source.getMetadata('/music/ghost.mp3'),
        throwsA(isA<SourceApiException>()),
      );
    });

    test('download is refused (read-only source)', () async {
      final LocalFolderSource source = LocalFolderSource(
        folders: const <String>['/music'],
        fs: buildMusicFs(),
      );
      expect(source.supportsDownload, isFalse);
      await expectLater(
        source.download(
          folderTrack(buildMusicFs(), '/music/Aurora/Nebula Drive/01 Starfield.mp3'),
          targetPath: '/tmp/x',
          quality: AudioQuality.high,
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  // The shared Stage 2.1 provider contract suite — proves the plugin
  // contributed source is indistinguishable from the built-in sources.
  runSourceProviderContract(
    'local-folder',
    () => LocalFolderSource(
      folders: const <String>['/music'],
      fs: buildMusicFs(),
    ),
    streamTrack: folderTrack(
      buildMusicFs(),
      '/music/Aurora/Nebula Drive/01 Starfield.mp3',
    ),
  );
}

/// Plugin whose init always throws (host isolation fixture).
class _ExplodingPlugin implements WavelyPlugin {
  @override
  PluginManifest get manifest => const PluginManifest(
        id: 'plugin.exploding',
        name: 'Exploding',
        version: '0.0.1',
        capabilities: <PluginCapability>[],
      );

  @override
  Future<void> init(PluginHostContext context) async {
    throw StateError('boom');
  }

  @override
  Future<void> dispose() async {}
}

/// Records registrations (host-context stand-in for direct plugin tests).
class _RecordingContext implements PluginHostContext {
  final List<SourceProvider> sources = <SourceProvider>[];

  @override
  void registerSource(SourceProvider source) => sources.add(source);
}

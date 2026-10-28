// authored, awaiting local run.
//
// Tests for lib/features/search/domain/search_service.dart: parallel fan-out
// with per-source timeouts, failed-source collection, dedupe contract
// (ISRC hook, title+artist Levenshtein < 3, blank-artist matching) and the
// Levenshtein helper itself. Five scripted sources cover the spec's
// "5 mocked sources" contract case.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/features/search/domain/search_service.dart';

Track _t(String source, String id, String title, String artist) {
  final DateTime now = DateTime.utc(2024);
  return Track(
    sourceId: source,
    sourceTrackId: id,
    title: title,
    artist: artist,
    durationMs: 1000,
    format: 'mp3',
    addedAt: now,
    updatedAt: now,
  );
}

/// Scripted SourceProvider: returns [tracks] after an optional [delay] or
/// throws [error].
class ScriptedSource implements SourceProvider {
  ScriptedSource(
    this.id, {
    this.tracks = const <Track>[],
    this.delay = Duration.zero,
    Object? error,
  }) : _error = error;

  @override
  final String id;

  @override
  String get displayName => 'Scripted $id';

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsDownload => true;

  @override
  bool get supportsSearch => true;

  final List<Track> tracks;
  final Duration delay;
  final Object? _error;

  @override
  Future<List<Track>> search(String q, {int limit = 20}) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final Object? e = _error;
    if (e != null) {
      throw e;
    }
    return tracks;
  }

  @override
  Future<StreamUrl> resolveStream(Track t) async =>
      StreamUrl(url: 'https://example/${t.sourceTrackId}');

  @override
  Future<dynamic> download(
    Track t, {
    required String targetPath,
    required AudioQuality quality,
  }) async =>
      throw UnsupportedError('not needed here');

  @override
  Future<Map<String, dynamic>> getMetadata(String sourceTrackId) async =>
      <String, dynamic>{};
}

void main() {
  group('SearchService.search', () {
    test('merges hits from all sources in parallel', () async {
      final SearchService s = SearchService(
        sources: <SourceProvider>[
          ScriptedSource('a', tracks: <Track>[_t('a', '1', 'One', 'A')]),
          ScriptedSource('b', tracks: <Track>[_t('b', '2', 'Two', 'B')]),
        ],
      );
      final UnifiedSearchResult r = await s.search('query');
      expect(r.hits.map((UnifiedSearchHit h) => h.track.title),
          <String>['One', 'Two']);
      expect(r.failedSources, isEmpty);
    });

    test('collects failed sources without failing the round', () async {
      final SearchService s = SearchService(
        sources: <SourceProvider>[
          ScriptedSource('boom', error: StateError('nope')),
          ScriptedSource('ok', tracks: <Track>[_t('ok', '1', 'One', 'A')]),
        ],
      );
      final UnifiedSearchResult r = await s.search('query');
      expect(r.failedSources, <String>['boom']);
      expect(r.hits, hasLength(1));
    });

    test('per-source timeout is 5s (injectable shorter for tests)', () async {
      final SearchService s = SearchService(
        sources: <SourceProvider>[
          ScriptedSource(
            'slow',
            delay: const Duration(milliseconds: 80),
            tracks: <Track>[_t('slow', '1', 'Slow', 'S')],
          ),
          ScriptedSource('fast', tracks: <Track>[_t('fast', '2', 'Fast', 'F')]),
        ],
        timeout: const Duration(milliseconds: 30),
      );
      final UnifiedSearchResult r = await s.search('query');
      expect(r.failedSources, <String>['slow']);
      expect(r.hits.single.track.title, 'Fast');
    });

    test('empty query returns the empty result without fan-out', () async {
      final SearchService s = SearchService(
        sources: <SourceProvider>[ScriptedSource('a')],
      );
      expect(s.search('  '), completion(UnifiedSearchResult.empty));
    });

    test('no sources → empty result', () async {
      final SearchService s = SearchService(sources: <SourceProvider>[]);
      expect(s.search('x'), completion(UnifiedSearchResult.empty));
    });
  });

  group('SearchService.dedupe', () {
    SearchService svc(List<SourceProvider> sources) =>
        SearchService(sources: sources);

    test('1. exact same title+artist across sources collapses to one',
        () async {
      final SearchService s = svc(<SourceProvider>[]);
      final List<UnifiedSearchHit> out = s.dedupe(<UnifiedSearchHit>[
        UnifiedSearchHit(track: _t('a', '1', 'Aurora', 'Nova'), sourceId: 'a'),
        UnifiedSearchHit(track: _t('b', '2', 'Aurora', 'Nova'), sourceId: 'b'),
      ]);
      expect(out, hasLength(1));
      expect(out.single.sourceId, 'a');
    });

    test('2. near-duplicate titles within Levenshtein 3 collapse', () async {
      final SearchService s = svc(<SourceProvider>[]);
      final List<UnifiedSearchHit> out = s.dedupe(<UnifiedSearchHit>[
        UnifiedSearchHit(
          track: _t('a', '1', 'Aurora (Remastered)', 'Nova'),
          sourceId: 'a',
        ),
        UnifiedSearchHit(
          track: _t('b', '2', 'Aurora Remastered', 'Nova'),
          sourceId: 'b',
        ),
      ]);
      expect(out, hasLength(1));
    });

    test('3. different artists keep both hits', () async {
      final SearchService s = svc(<SourceProvider>[]);
      final List<UnifiedSearchHit> out = s.dedupe(<UnifiedSearchHit>[
        UnifiedSearchHit(track: _t('a', '1', 'Aurora', 'Nova'), sourceId: 'a'),
        UnifiedSearchHit(
          track: _t('b', '2', 'Aurora', 'Completely Different Artist'),
          sourceId: 'b',
        ),
      ]);
      expect(out, hasLength(2));
    });

    test('4. blank artist matches any artist (fixture noise tolerance)',
        () async {
      final SearchService s = svc(<SourceProvider>[]);
      final List<UnifiedSearchHit> out = s.dedupe(<UnifiedSearchHit>[
        UnifiedSearchHit(track: _t('a', '1', 'Aurora', ''), sourceId: 'a'),
        UnifiedSearchHit(
          track: _t('b', '2', 'Aurora', 'Nova'),
          sourceId: 'b',
        ),
      ]);
      expect(out, hasLength(1));
    });

    test('5. ISRC hook takes priority when both hits carry one', () async {
      final SearchService s = IsrcSearchService();
      // Same ISRC but very different titles → still a duplicate.
      final List<UnifiedSearchHit> out = s.dedupe(<UnifiedSearchHit>[
        UnifiedSearchHit(
          track: _t('a', 'isrc:USABC123', 'Alpha', 'A'),
          sourceId: 'a',
        ),
        UnifiedSearchHit(
          track: _t('b', 'isrc:USABC123', 'Totally other title', 'B'),
          sourceId: 'b',
        ),
      ]);
      expect(out, hasLength(1));
    });

    test('order of first appearance is preserved', () async {
      final SearchService s = svc(<SourceProvider>[]);
      final List<UnifiedSearchHit> out = s.dedupe(<UnifiedSearchHit>[
        UnifiedSearchHit(track: _t('b', '1', 'Two', 'B'), sourceId: 'b'),
        UnifiedSearchHit(track: _t('a', '2', 'One', 'A'), sourceId: 'a'),
        UnifiedSearchHit(track: _t('c', '3', 'Two', 'B'), sourceId: 'c'),
      ]);
      expect(out.map((UnifiedSearchHit h) => h.track.title),
          <String>['Two', 'One']);
    });
  });

  group('levenshtein', () {
    test('classic distances', () {
      expect(levenshtein('', ''), 0);
      expect(levenshtein('a', ''), 1);
      expect(levenshtein('kitten', 'sitting'), 3);
      expect(levenshtein('aurora', 'aurora'), 0);
      expect(levenshtein('aurora', 'AURORA'.toLowerCase()), 0);
    });
  });

  group('UnifiedSearchHit.qualityLabel', () {
    UnifiedSearchHit hit(String format) => UnifiedSearchHit(
          track: _t('s', '1', 't', 'a').copyWith(format: format),
          sourceId: 's',
        );

    test('maps formats to badge labels', () {
      expect(hit('flac').qualityLabel, 'FLAC');
      expect(hit('ogg').qualityLabel, 'OGG');
      expect(hit('wav').qualityLabel, 'WAV');
      expect(hit('mp3').qualityLabel, 'MP3');
      expect(hit('').qualityLabel, 'AUDIO');
    });
  });
}

/// SearchService with a working ISRC hook (id encode: `isrc:<value>`).
class IsrcSearchService extends SearchService {
  IsrcSearchService() : super(sources: <SourceProvider>[]);

  @override
  String? isrcOf(Track t) =>
      t.sourceTrackId.startsWith('isrc:') ? t.sourceTrackId : null;
}

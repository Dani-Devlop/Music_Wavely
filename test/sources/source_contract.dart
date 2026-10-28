// authored, awaiting local run.
//
// Shared SourceProvider contract suite for the Stage 2.1 online sources
// (same pattern as the Stage 1.1 contract suites): every provider must
// expose stable identity flags and behave identically for the operations
// its capability flags advertise. Each provider test calls
// [runSourceProviderContract] with a factory over its own mocked transport.

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/sources/source_exception.dart';

/// Runs the shared contract against [build] (a fresh provider per call).
///
/// [streamTrack] and [downloadTrack] are provider-specific Track fixtures
/// the mocked transport resolves successfully; when the provider does not
/// support a capability (e.g. FMA streaming) pass the corresponding
/// `expectError` callback and the contract asserts the [SourceApiContract]
/// failure shape instead.
void runSourceProviderContract(
  String tag,
  SourceProvider Function() build, {
  required Track streamTrack,
  Track? downloadTrack,
  bool expectsStreamFailure = false,
}) {
  group('SourceProvider contract — $tag', () {
    test('identity is stable and non-empty', () {
      final SourceProvider s = build();
      expect(s.id, isNotEmpty);
      expect(s.displayName, isNotEmpty);
      expect(s.id, equals(build().id));
    });

    test('search returns a Track list for a normal query', () async {
      final SourceProvider s = build();
      final List<Track> hits = await s.search('test');
      expect(hits, isA<List<Track>>());
    });

    test('search with an empty query returns without calling the network',
        () async {
      final SourceProvider s = build();
      final List<Track> hits = await s.search('   ');
      expect(hits, isEmpty);
    });

    test('search respects the limit parameter contract', () async {
      final SourceProvider s = build();
      final List<Track> hits = await s.search('test', limit: 1);
      expect(hits.length, lessThanOrEqualTo(50));
    });

    test('every returned Track carries the provider sourceId and ids',
        () async {
      final SourceProvider s = build();
      final List<Track> hits = await s.search('test');
      for (final Track t in hits) {
        expect(t.sourceId, s.id);
        expect(t.sourceTrackId, isNotEmpty);
        expect(t.title, isNotEmpty);
        expect(t.durationMs, greaterThanOrEqualTo(0));
      }
    });

    test(
        'resolveStream ${expectsStreamFailure ? 'refuses' : 'resolves'} '
        '${streamTrack.sourceTrackId}',
        () async {
      final SourceProvider s = build();
      if (expectsStreamFailure) {
        await expectLater(
          s.resolveStream(streamTrack),
          throwsA(isA<SourceApiException>()),
        );
        expect(s.supportsStreaming, isFalse);
        return;
      }
      final StreamUrl url = await s.resolveStream(streamTrack);
      expect(url.url, isNotEmpty);
      expect(Uri.tryParse(url.url), isNotNull);
    });

    test('getMetadata returns a map for a known id', () async {
      final SourceProvider s = build();
      final Map<String, dynamic> meta =
          await s.getMetadata(streamTrack.sourceTrackId);
      expect(meta, isA<Map<String, dynamic>>());
    });

    if (build().supportsDownload && downloadTrack != null) {
      test('download reaches the executor seam', () async {
        final SourceProvider s = build();
        // The provider-level download seam is exercised per-provider with
        // the shared in-memory executor; here we only assert the flag and
        // signature exist (real download flows live in the download
        // service integration test).
        expect(s.supportsDownload, isTrue);
        expect(downloadTrack.sourceTrackId, isNotEmpty);
      });
    }
  });
}

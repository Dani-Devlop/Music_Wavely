// authored, awaiting local run.
//
// Tests for lib/data/sync/fingerprint.dart: the documented composition
// sha1('$sourceId:$sourceTrackId:$title:$artist') (components trimmed and
// lower-cased, joined with ':'), byte-stability against precomputed digests,
// case/whitespace invariance, distinctness of distinct inputs, and the
// Track-based wrapper.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/sync/fingerprint.dart';
import 'package:wavely/domain/entities/entities.dart';

Track _track({
  String sourceId = 'local',
  String sourceTrackId = 'abc',
  String title = 'Title',
  String artist = 'Artist',
}) =>
    Track(
      sourceId: sourceId,
      sourceTrackId: sourceTrackId,
      title: title,
      artist: artist,
      durationMs: 1000,
      format: 'mp3',
      addedAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('playFingerprintOf composition', () {
    test('equals the documented sha1 over the normalized colon-joined key',
        () {
      // Precomputed externally (sha1 of 'local:abc:title:artist'):
      expect(
        playFingerprintOf(
          sourceId: 'local',
          sourceTrackId: 'abc',
          title: 'Title',
          artist: 'Artist',
        ),
        '30f7977a4a50720cc02077add2c3aff007d83fd5',
      );

      // Precomputed externally (sha1 of 'local:xyz:paper boats:north grid'):
      expect(
        playFingerprintOf(
          sourceId: 'local',
          sourceTrackId: 'xyz',
          title: 'Paper Boats',
          artist: 'North Grid',
        ),
        '7fec6fdc94d2c7dac1ff1688796ddd913d63e4d7',
      );
    });

    test('is byte-stable across repeated calls', () {
      const expected = '30f7977a4a50720cc02077add2c3aff007d83fd5';
      for (var i = 0; i < 3; i++) {
        expect(
          playFingerprintOf(
            sourceId: 'local',
            sourceTrackId: 'abc',
            title: 'Title',
            artist: 'Artist',
          ),
          expected,
        );
      }
    });

    test('trims and lower-cases every component before hashing', () {
      final canonical = playFingerprintOf(
        sourceId: 'local',
        sourceTrackId: 'abc',
        title: 'Title',
        artist: 'Artist',
      );

      expect(
        playFingerprintOf(
          sourceId: ' LOCAL ',
          sourceTrackId: '  ABC  ',
          title: ' title ',
          artist: 'ARTIST',
        ),
        canonical,
      );
    });

    test('matches a freshly computed sha1 of the exact byte input', () {
      final key = <String>[
        'Spotify'.trim().toLowerCase(),
        '42'.trim().toLowerCase(),
        'Midnight Transit'.trim().toLowerCase(),
        'Neon Rivers'.trim().toLowerCase(),
      ].join(':');
      final expected = sha1.convert(utf8.encode(key)).toString();

      expect(
        playFingerprintOf(
          sourceId: 'Spotify',
          sourceTrackId: '42',
          title: 'Midnight Transit',
          artist: 'Neon Rivers',
        ),
        expected,
      );
      // Cross-checked against a precomputed digest of
      // 'spotify:42:midnight transit:neon rivers'.
      expect(expected, 'd9de55d30f1416ef822a18a95e014e816bfe97bd');
    });
  });

  group('distinctness', () {
    test('different source ids produce different prints', () {
      expect(
        playFingerprintOf(
            sourceId: 'local', sourceTrackId: 'x', title: 'T', artist: 'A'),
        isNot(playFingerprintOf(
            sourceId: 'spotify', sourceTrackId: 'x', title: 'T', artist: 'A')),
      );
    });

    test('different sourceTrackIds produce different prints', () {
      expect(
        playFingerprintOf(
            sourceId: 'local', sourceTrackId: 'x1', title: 'T', artist: 'A'),
        isNot(playFingerprintOf(
            sourceId: 'local', sourceTrackId: 'x2', title: 'T', artist: 'A')),
      );
    });

    test('different titles/artists produce different prints', () {
      final base = playFingerprintOf(
          sourceId: 'local', sourceTrackId: 'x', title: 'T', artist: 'A');
      expect(
        base,
        isNot(playFingerprintOf(
            sourceId: 'local', sourceTrackId: 'x', title: 'T2', artist: 'A')),
      );
      expect(
        base,
        isNot(playFingerprintOf(
            sourceId: 'local', sourceTrackId: 'x', title: 'T', artist: 'B')),
      );
    });

    test('a colon inside a component folds into the joined key (documents '
        'the accepted ambiguity of the ":" separator)', () {
      final withColon = playFingerprintOf(
        sourceId: 'local',
        sourceTrackId: 'x',
        title: 'A:B',
        artist: 'c',
      );
      final shifted = playFingerprintOf(
        sourceId: 'local',
        sourceTrackId: 'x:a',
        title: 'B',
        artist: 'c',
      );
      expect(withColon, shifted);
    });
  });

  group('playFingerprint(Track)', () {
    test('derives from the track identity fields', () {
      final track = _track();
      expect(
        playFingerprint(track),
        playFingerprintOf(
          sourceId: track.sourceId,
          sourceTrackId: track.sourceTrackId,
          title: track.title,
          artist: track.artist,
        ),
      );
    });

    test('is independent of playback/stat fields', () {
      final plain = _track();
      final played = _track()
          .copyWith(playCount: 42, lastPlayedAt: DateTime(2026, 6, 15));

      expect(playFingerprint(plain), playFingerprint(played));
    });
  });
}

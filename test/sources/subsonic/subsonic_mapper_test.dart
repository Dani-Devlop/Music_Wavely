// authored, awaiting local run.
//
// Unit tests for lib/sources/subsonic/subsonic_mapper.dart: Child JSON →
// Track mapping (happy path, missing fields, directories, content-type
// fallback, created-timestamp parsing, list mapping).

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/sources/subsonic/subsonic_mapper.dart';

SubsonicMapper mapperWithFixedNow() => SubsonicMapper(
      now: () => DateTime.utc(2026, 1, 30, 12),
    );

void main() {
  group('SubsonicChild.fromJson', () {
    test('parses a full child', () {
      final SubsonicChild c = SubsonicChild.fromJson(<String, dynamic>{
        'id': 'abc123',
        'title': 'Song',
        'artist': 'Artist',
        'album': 'Album',
        'genre': 'Rock',
        'duration': 180,
        'bitRate': 320,
        'suffix': 'flac',
        'contentType': 'audio/flac',
        'size': 12345,
        'coverArt': 'al-1',
        'track': 3,
        'year': 2020,
        'created': '2024-01-01T10:00:00Z',
      });
      expect(c.id, 'abc123');
      expect(c.title, 'Song');
      expect(c.artist, 'Artist');
      expect(c.album, 'Album');
      expect(c.genre, 'Rock');
      expect(c.durationSeconds, 180);
      expect(c.bitRate, 320);
      expect(c.suffix, 'flac');
      expect(c.size, 12345);
      expect(c.coverArtId, 'al-1');
      expect(c.trackNumber, 3);
      expect(c.year, 2020);
      expect(c.isPlayable, isTrue);
    });

    test('tolerates missing fields and numeric-string ids', () {
      final SubsonicChild c =
          SubsonicChild.fromJson(<String, dynamic>{'id': 42});
      expect(c.id, '42');
      expect(c.title, '');
      expect(c.isPlayable, isFalse);
    });

    test('marks directories as not playable', () {
      final SubsonicChild c = SubsonicChild.fromJson(
        <String, dynamic>{'id': 'dir-1', 'title': 'Dir', 'isDir': true},
      );
      expect(c.isDir, isTrue);
      expect(c.isPlayable, isFalse);
    });
  });

  group('SubsonicMapper.fromChild', () {
    test('maps a full child to a Track with subsonic sourceId', () {
      final Track? t = mapperWithFixedNow().fromChild(
        SubsonicChild.fromJson(<String, dynamic>{
          'id': 'tr-1',
          'title': 'Aurora',
          'artist': 'Nova',
          'album': 'Lights',
          'genre': 'Ambient',
          'duration': 200,
          'bitRate': 256,
          'suffix': 'mp3',
          'created': '2024-06-01T08:30:00Z',
        }),
      );
      expect(t, isNotNull);
      expect(t!.sourceId, 'subsonic');
      expect(t.sourceTrackId, 'tr-1');
      expect(t.title, 'Aurora');
      expect(t.artist, 'Nova');
      expect(t.album, 'Lights');
      expect(t.genre, 'Ambient');
      expect(t.durationMs, 200 * 1000);
      expect(t.bitrate, 256);
      expect(t.format, 'mp3');
      expect(t.addedAt, DateTime.utc(2024, 6, 1, 8, 30));
    });

    test('falls back to content-type for the format when suffix missing', () {
      final SubsonicMapper mapper = mapperWithFixedNow();
      expect(
        mapper
            .fromChild(
              SubsonicChild.fromJson(<String, dynamic>{
                'id': '1',
                'title': 'x',
                'contentType': 'audio/flac',
              }),
            )!
            .format,
        'flac',
      );
      expect(
        mapper
            .fromChild(
              SubsonicChild.fromJson(<String, dynamic>{
                'id': '2',
                'title': 'x',
                'contentType': 'audio/mpeg',
              }),
            )!
            .format,
        'mp3',
      );
      expect(
        mapper
            .fromChild(
              SubsonicChild.fromJson(<String, dynamic>{
                'id': '3',
                'title': 'x',
                'contentType': 'application/ogg',
              }),
            )!
            .format,
        'ogg',
      );
    });

    test('returns null for directories and unnamed children', () {
      final SubsonicMapper mapper = mapperWithFixedNow();
      expect(
        mapper.fromChild(
          SubsonicChild.fromJson(
            <String, dynamic>{'id': 'd', 'title': 'd', 'isDir': true},
          ),
        ),
        isNull,
      );
      expect(
        mapper.fromChild(
          SubsonicChild.fromJson(<String, dynamic>{'id': 'e'}),
        ),
        isNull,
      );
    });

    test('uses the injected clock when created is absent', () {
      final Track? t = mapperWithFixedNow().fromChild(
        SubsonicChild.fromJson(
          <String, dynamic>{'id': 'x', 'title': 'x'},
        ),
      );
      expect(t!.addedAt, DateTime.utc(2026, 1, 30, 12));
    });
  });

  group('SubsonicMapper.fromChildList', () {
    test('maps a song list and skips unparsable entries', () {
      final List<Track> tracks = mapperWithFixedNow().fromChildList(
        <dynamic>[
          <String, dynamic>{'id': '1', 'title': 'One'},
          <String, dynamic>{'id': '2', 'title': 'Two', 'isDir': true},
          <String, dynamic>{},
          <String, dynamic>{'id': '3', 'title': 'Three'},
        ],
      );
      expect(tracks.map((Track t) => t.title), <String>['One', 'Three']);
    });

    test('returns empty for garbage input', () {
      expect(
        mapperWithFixedNow().fromChildList(<dynamic>['nope', 42, null]),
        isEmpty,
      );
    });
  });
}

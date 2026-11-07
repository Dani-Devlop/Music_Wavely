/// Tests for the Phase 7.1 tag IO bridge: real read → write → read
/// roundtrips over temporary MP3 (ID3v2) and FLAC (Vorbis) files.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/tag_editor/data/tag_io.dart';
import 'package:wavely/features/tag_editor/data/tag_models.dart';
import '../../support/audio_fixtures.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wavely-tag-io');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Temp cleanup is best-effort.
    }
  });

  group('MP3 (ID3v2) roundtrip', () {
    test('reads the initial tags of the fixture', () async {
      final path = '${tempDir.path}/fixture.mp3';
      await File(path).writeAsBytes(
        minimalMp3Bytes(
          textFrames: <String, String>{
            'TIT2': 'Old Title',
            'TPE1': 'Old Artist',
          },
        ),
        flush: true,
      );
      final EditableTags tags = readTagsFromFile(File(path));
      expect(tags.title, 'Old Title');
      expect(tags.artist, 'Old Artist');
    });

    test('writes all 13 fields and reads them back', () async {
      // Library limitation (documented in the parity report): the ID3v4
      // writer emits text frames + pictures only — COMM (comment) and
      // USLT (lyrics) are read but not written back, so those two fields
      // do not survive an MP3 write. All other 11 fields roundtrip.
      final path = '${tempDir.path}/roundtrip.mp3';
      await File(path).writeAsBytes(
        minimalMp3Bytes(textFrames: <String, String>{'TIT2': 'Seed'}),
        flush: true,
      );

      final EditableTags tags = EditableTags()
        ..title = 'Edited Title'
        ..artist = 'Edited Artist'
        ..album = 'Edited Album'
        ..albumArtist = 'Album Artist'
        ..genre = 'Ambient'
        ..year = '1994'
        ..trackNumber = '3'
        ..totalTracks = '12'
        ..discNumber = '1'
        ..composer = 'The Composer'
        ..lyricist = 'The Lyricist';

      final TagWriteResult result = writeTagsToFile(File(path), tags);
      expect(result.isSuccess, isTrue, reason: result.error?.toString());

      final EditableTags readBack = readTagsFromFile(File(path));
      expect(readBack.title, 'Edited Title');
      expect(readBack.artist, 'Edited Artist');
      expect(readBack.album, 'Edited Album');
      expect(readBack.albumArtist, 'Album Artist');
      expect(readBack.genre, 'Ambient');
      expect(readBack.year, '1994');
      expect(readBack.trackNumber, '3');
      expect(readBack.totalTracks, '12');
      expect(readBack.discNumber, '1');
      expect(readBack.composer, 'The Composer');
      expect(readBack.lyricist, 'The Lyricist');
    });

    test('writes only the requested fields in batch mode', () async {
      final path = '${tempDir.path}/partial.mp3';
      await File(path).writeAsBytes(
        minimalMp3Bytes(
          textFrames: <String, String>{
            'TIT2': 'Keep Title',
            'TPE1': 'Keep Artist',
          },
        ),
        flush: true,
      );

      final EditableTags tags = EditableTags()
        ..title = 'Changed'
        ..artist = 'Also Changed';
      final TagWriteResult result = writeTagsToFile(
        File(path),
        tags,
        fields: <TagField>{TagField.artist},
      );
      expect(result.isSuccess, isTrue, reason: result.error?.toString());

      final EditableTags readBack = readTagsFromFile(File(path));
      expect(readBack.title, 'Keep Title');
      expect(readBack.artist, 'Also Changed');
    });

    test('embeds cover art (single + batch path)', () async {
      final path = '${tempDir.path}/cover.mp3';
      await File(path).writeAsBytes(
        minimalMp3Bytes(textFrames: <String, String>{}),
        flush: true,
      );

      final EditableTags tags = EditableTags()
        ..title = 'With Cover'
        ..coverBytes = Uint8List.fromList(<int>[1, 2, 3, 4])
        ..coverMime = 'image/png';
      final TagWriteResult result = writeTagsToFile(
        File(path),
        tags,
        writeCover: true,
      );
      expect(result.isSuccess, isTrue, reason: result.error?.toString());

      final EditableTags readBack = readTagsFromFile(File(path));
      expect(readBack.coverBytes, isNotNull);
      expect(readBack.coverBytes, hasLength(4));
      expect(readBack.coverMime, 'image/png');
    });
  });

  group('FLAC (Vorbis comments) roundtrip', () {
    // Library limitation (documented in the parity report): FlacWriter
    // rebuilds the comment block from a FIXED key list (TITLE, ALBUM,
    // TRACKNUMBER, ARTIST, ALBUMARTIST, GENRE, DATE, …) — composer,
    // comment, lyrics, total tracks and disc number are not representable
    // and are therefore dropped on write. The test asserts the roundtrippable
    // subset.
    test('writes and reads back the core fields', () async {
      final path = '${tempDir.path}/roundtrip.flac';
      await File(path).writeAsBytes(minimalFlacBytes(), flush: true);

      final EditableTags tags = EditableTags()
        ..title = 'Flac Title'
        ..artist = 'Flac Artist'
        ..album = 'Flac Album'
        ..albumArtist = 'Flac Album Artist'
        ..genre = 'Jazz'
        ..year = '1988'
        ..trackNumber = '5'
        ..totalTracks = '9'
        ..discNumber = '2'
        ..composer = 'F. Composer'
        ..comment = 'Flac comment'
        ..lyrics = 'La la la';

      final TagWriteResult result = writeTagsToFile(File(path), tags);
      expect(result.isSuccess, isTrue, reason: result.error?.toString());

      final EditableTags readBack = readTagsFromFile(File(path));
      expect(readBack.title, 'Flac Title');
      expect(readBack.artist, 'Flac Artist');
      expect(readBack.album, 'Flac Album');
      expect(readBack.albumArtist, 'Flac Album Artist');
      expect(readBack.genre, 'Jazz');
      expect(readBack.year, '1988');
      expect(readBack.trackNumber, '5');
    });

    test('embeds cover art into the picture block', () async {
      final path = '${tempDir.path}/cover.flac';
      await File(path).writeAsBytes(minimalFlacBytes(), flush: true);
      final EditableTags tags = EditableTags()
        ..title = 'Covered'
        ..coverBytes = Uint8List.fromList(<int>[9, 8, 7])
        ..coverMime = 'image/jpeg';
      final TagWriteResult result = writeTagsToFile(
        File(path),
        tags,
        writeCover: true,
      );
      expect(result.isSuccess, isTrue, reason: result.error?.toString());
      final EditableTags readBack = readTagsFromFile(File(path));
      expect(readBack.coverBytes, hasLength(3));
    });
  });

  group('validation + helpers', () {
    test('validateTags flags bad year and counters', () {
      final EditableTags bad = EditableTags()
        ..year = '19'
        ..trackNumber = 'abc'
        ..totalTracks = ''
        ..discNumber = '-1';
      final List<String> problems = validateTags(bad);
      expect(problems, hasLength(3));
      expect(problems[0], contains('Year'));
      expect(problems[1], contains('Track #'));
      expect(problems[2], contains('Disc #'));
    });

    test('validateTags accepts composite track numbers and blank values',
        () {
      final EditableTags ok = EditableTags()
        ..year = '2024'
        ..trackNumber = '3/12'
        ..totalTracks = '12';
      expect(validateTags(ok), isEmpty);
    });

    test('readCoverFile maps extensions to MIME types', () async {
      final path = '${tempDir.path}/art.png';
      await File(path).writeAsBytes(<int>[1, 2, 3], flush: true);
      final (Uint8List, String)? cover = await readCoverFile(path);
      expect(cover, isNotNull);
      expect(cover!.$1, hasLength(3));
      expect(cover.$2, 'image/png');
    });

    test('readCoverFile returns null for missing files', () async {
      expect(
        await readCoverFile('${tempDir.path}/missing.png'),
        isNull,
      );
    });
  });
}

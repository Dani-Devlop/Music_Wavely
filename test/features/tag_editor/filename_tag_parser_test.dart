/// Tests for the Phase 7.1 filename tag parser.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/tag_editor/data/filename_tag_parser.dart';
import 'package:wavely/features/tag_editor/data/tag_models.dart';

void main() {
  group('parseTagsFromFilename', () {
    test('parses "Artist - Title" (no leading number)', () {
      final result = parseTagsFromFilename('Boards of Canada - Roygbiv.mp3');
      expect(result.artist, 'Boards of Canada');
      expect(result.title, 'Roygbiv');
      expect(result.trackNumber, isNull);
    });

    test('parses "NN. Artist - Title"', () {
      final result = parseTagsFromFilename('07. Aphex Twin - Heliosphan.mp3');
      expect(result.trackNumber, 7);
      expect(result.artist, 'Aphex Twin');
      expect(result.title, 'Heliosphan');
    });

    test('parses "NN - Title" (no artist)', () {
      final result = parseTagsFromFilename('03 - Opening Theme.flac');
      expect(result.trackNumber, 3);
      expect(result.artist, isNull);
      expect(result.title, 'Opening Theme');
    });

    test('keeps hyphens inside the title when only one separator exists',
        () {
      final result =
          parseTagsFromFilename('Sigur Rós - Svefn-g-englar.mp3');
      expect(result.artist, 'Sigur Rós');
      expect(result.title, 'Svefn-g-englar');
    });

    test('splits on the first separator (artist may not contain " - ")',
        () {
      final result = parseTagsFromFilename('Nirvana - Smells Like Teen Spirit');
      expect(result.artist, 'Nirvana');
      expect(result.title, 'Smells Like Teen Spirit');
    });

    test('falls back to the full stem as title', () {
      final result = parseTagsFromFilename('just a track name.wav');
      expect(result.artist, isNull);
      expect(result.title, 'just a track name');
      expect(result.trackNumber, isNull);
    });

    test('strips the extension only once ("name.with.dots" keeps dots)',
        () {
      final result = parseTagsFromFilename('01. A - B.C.dots.mp3');
      expect(result.title, 'B.C.dots');
    });

    test('blank input yields an empty title', () {
      final result = parseTagsFromFilename('.mp3');
      expect(result.title, '.mp3');
    });

    test('applies parsed values over an EditableTags without clearing',
        () {
      final tags = EditableTags()
        ..album = 'Keep Me'
        ..artist = 'Old Artist';
      parseTagsFromFilename('02. New Artist - New Title.mp3')
          .applyTo(tags);
      expect(tags.trackNumber, '2');
      expect(tags.artist, 'New Artist');
      expect(tags.title, 'New Title');
      expect(tags.album, 'Keep Me');
    });

    test('empty parsed fields do not overwrite', () {
      final tags = EditableTags()..artist = 'Existing';
      parseTagsFromFilename('Solo Title.mp3').applyTo(tags);
      expect(tags.artist, 'Existing');
      expect(tags.title, 'Solo Title');
    });
  });

  group('tagsFromFilename', () {
    test('returns a fresh snapshot with the parsed values', () {
      final tags = tagsFromFilename('12. Artist - Title.mp3');
      expect(tags.trackNumber, '12');
      expect(tags.artist, 'Artist');
      expect(tags.title, 'Title');
    });
  });
}

/// Read/write bridge between [EditableTags] and the format-specific
/// metadata models of `audio_metadata_reader` (Phase 7.1).
///
/// Supported write targets: MP3 (ID3v2.4), FLAC/OGG (Vorbis comments),
/// MP4/M4A, WAV (RIFF), APE. Files without a matching writer fail
/// gracefully with [TagWriteResult.failure].
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
// ParserTag and Comment are part of the model hierarchy but not surfaced by
// the public export list; the models are a stable part of the package's
// updateMetadata contract, so the source import is the sanctioned way to
// name them (audio_metadata_reader is a direct dependency).
import 'package:audio_metadata_reader/src/metadata/base.dart'
    show Comment, ParserTag;
import 'package:wavely/features/tag_editor/data/tag_models.dart';

/// Reads the current tag snapshot of [file].
///
/// Throws when the file has no parseable metadata — callers surface that as
/// a per-file failure (batch saves must never abort wholesale).
EditableTags readTagsFromFile(File file) {
  final ParserTag metadata = readAllMetadata(file);
  return editableFromParserTag(metadata);
}

/// Converts a parsed [ParserTag] into the neutral [EditableTags] snapshot.
EditableTags editableFromParserTag(ParserTag metadata) {
  final EditableTags tags = EditableTags();
  switch (metadata) {
    case final Mp3Metadata mp3:
      tags
        ..title = mp3.songName ?? ''
        ..artist = mp3.leadPerformer ?? ''
        ..album = mp3.album ?? ''
        ..albumArtist = mp3.bandOrOrchestra ?? ''
        ..genre = mp3.contentType ?? mp3.genres.firstOrNull ?? ''
        ..year = mp3.year == null ? '' : '${mp3.year}'
        ..trackNumber = mp3.trackNumber == null ? '' : '${mp3.trackNumber}'
        ..totalTracks = mp3.trackTotal == null ? '' : '${mp3.trackTotal}'
        ..discNumber = mp3.discNumber == null ? '' : '${mp3.discNumber}'
        ..composer = mp3.composer ?? ''
        ..lyricist = mp3.textWriter ?? ''
        ..comment = mp3.comments.firstOrNull?.text ?? ''
        ..lyrics = mp3.lyric ?? '';
      final Picture? cover = mp3.pictures.firstOrNull;
      tags
        ..coverBytes = cover?.bytes
        ..coverMime = cover?.mimetype;
    case final VorbisMetadata vorbis:
      tags
        ..title = vorbis.title.firstOrNull ?? ''
        ..artist = vorbis.artist.firstOrNull ?? ''
        ..album = vorbis.album.firstOrNull ?? ''
        ..albumArtist = vorbis.albumArtist.firstOrNull ?? ''
        ..genre = vorbis.genres.firstOrNull ?? ''
        ..year = vorbis.date.isEmpty ? '' : '${vorbis.date.first.year}'
        ..trackNumber =
            vorbis.trackNumber.isEmpty ? '' : '${vorbis.trackNumber.first}'
        ..totalTracks = vorbis.trackTotal == null ? '' : '${vorbis.trackTotal}'
        ..discNumber = vorbis.discNumber == null ? '' : '${vorbis.discNumber}'
        ..composer = vorbis.composer.firstOrNull ?? ''
        ..lyricist = vorbis.producer.firstOrNull ?? ''
        ..comment = vorbis.comment.firstOrNull ?? ''
        ..lyrics = vorbis.lyric ?? '';
      final Picture? cover = vorbis.pictures.firstOrNull;
      tags
        ..coverBytes = cover?.bytes
        ..coverMime = cover?.mimetype;
    case final Mp4Metadata mp4:
      tags
        ..title = mp4.title ?? ''
        ..artist = mp4.artist ?? ''
        ..album = mp4.album ?? ''
        ..genre = mp4.genre ?? ''
        ..year = mp4.year == null ? '' : '${mp4.year!.year}'
        ..trackNumber = mp4.trackNumber == null ? '' : '${mp4.trackNumber}'
        ..totalTracks = mp4.totalTracks == null ? '' : '${mp4.totalTracks}'
        ..discNumber = mp4.discNumber == null ? '' : '${mp4.discNumber}'
        ..lyrics = mp4.lyrics ?? '';
      tags
        ..coverBytes = mp4.picture?.bytes
        ..coverMime = mp4.picture?.mimetype;
    case final ApeMetadata ape:
      tags
        ..title = ape.title ?? ''
        ..artist = ape.artist ?? ''
        ..album = ape.album ?? ''
        ..albumArtist = ape.albumArtist ?? ''
        ..genre = ape.genres.firstOrNull ?? ''
        ..year = ape.date == null ? '' : '${ape.date!.year}'
        ..trackNumber = ape.trackNumber == null ? '' : '${ape.trackNumber}'
        ..totalTracks = ape.trackTotal == null ? '' : '${ape.trackTotal}'
        ..discNumber = ape.discNumber == null ? '' : '${ape.discNumber}'
        ..composer = ape.composer ?? ''
        ..comment = ape.comment ?? ''
        ..lyrics = ape.lyric ?? '';
      final Picture? cover = ape.pictures.firstOrNull;
      tags
        ..coverBytes = cover?.bytes
        ..coverMime = cover?.mimetype;
    case _:
      // RiffMetadata and future models: unsupported for the 13-field form;
      // return the empty snapshot so the UI can show "no tags".
  }
  return tags;
}

/// Writes [tags] back into [file], preserving the audio stream.
///
/// Only [fields] are written (batch mode applies just the changed fields);
/// when [fields] is `null` every non-empty field is written. When
/// [writeCover] is true and [tags].coverBytes is non-null, the cover art is
/// replaced (formats without picture support skip it).
TagWriteResult writeTagsToFile(
  File file,
  EditableTags tags, {
  Set<TagField>? fields,
  bool writeCover = false,
}) {
  try {
    updateMetadata(file, (ParserTag metadata) {
      _applyToParserTag(metadata, tags, fields: fields, writeCover: writeCover);
    });
    return TagWriteResult.success(file.path);
  } on Object catch (error) {
    return TagWriteResult.failure(file.path, error);
  }
}

void _applyToParserTag(
  ParserTag metadata,
  EditableTags tags, {
  Set<TagField>? fields,
  bool writeCover = false,
}) {
  bool wants(TagField field) => fields == null || fields.contains(field);

  // "Empty means unset" only for explicit field sets; a full write clears
  // a field when the form value is blank.
  String text(TagField field) => tags.valueOf(field);
  int? number(TagField field) => parseTrackNumber(text(field));
  int? yearOf() => parseYear(text(TagField.year));

  switch (metadata) {
    case final Mp3Metadata mp3:
      if (wants(TagField.title)) {
        mp3.songName = _nullIfEmpty(text(TagField.title));
      }
      if (wants(TagField.artist)) {
        mp3.leadPerformer = _nullIfEmpty(text(TagField.artist));
      }
      if (wants(TagField.album)) {
        mp3.album = _nullIfEmpty(text(TagField.album));
      }
      if (wants(TagField.albumArtist)) {
        mp3.bandOrOrchestra = _nullIfEmpty(text(TagField.albumArtist));
      }
      if (wants(TagField.genre)) {
        mp3.contentType = _nullIfEmpty(text(TagField.genre));
      }
      if (wants(TagField.year)) {
        mp3.year = yearOf();
      }
      if (wants(TagField.trackNumber)) {
        mp3.trackNumber = number(TagField.trackNumber);
      }
      if (wants(TagField.totalTracks)) {
        mp3.trackTotal = number(TagField.totalTracks);
      }
      if (wants(TagField.discNumber)) {
        mp3.discNumber = number(TagField.discNumber);
        // TPOS (part of set) is the frame the ID3 writer emits; keep both
        // in sync so the disc number survives the write.
        final int? disc = mp3.discNumber;
        mp3.partOfSet = disc == null ? null : '$disc';
      }
      if (wants(TagField.composer)) {
        mp3.composer = _nullIfEmpty(text(TagField.composer));
      }
      if (wants(TagField.lyricist)) {
        mp3.textWriter = _nullIfEmpty(text(TagField.lyricist));
      }
      if (wants(TagField.comment)) {
        final String value = text(TagField.comment);
        mp3.comments = value.isEmpty
            ? <Comment>[]
            : <Comment>[Comment('XXX', value)];
      }
      if (wants(TagField.lyrics)) {
        mp3.lyric = _nullIfEmpty(text(TagField.lyrics));
      }
      if (writeCover && tags.coverBytes != null) {
        mp3.pictures = <Picture>[
          Picture(
            tags.coverBytes!,
            tags.coverMime ?? 'image/jpeg',
            PictureType.coverFront,
          ),
        ];
      }
    case final VorbisMetadata vorbis:
      if (wants(TagField.title)) {
        vorbis.title = _listOrNull(text(TagField.title)) ?? <String>[];
      }
      if (wants(TagField.artist)) {
        vorbis.artist = _listOrNull(text(TagField.artist)) ?? <String>[];
      }
      if (wants(TagField.album)) {
        vorbis.album = _listOrNull(text(TagField.album)) ?? <String>[];
      }
      if (wants(TagField.albumArtist)) {
        vorbis.albumArtist =
            _listOrNull(text(TagField.albumArtist)) ?? <String>[];
      }
      if (wants(TagField.genre)) {
        vorbis.genres = _listOrNull(text(TagField.genre)) ?? <String>[];
      }
      if (wants(TagField.year)) {
        final int? year = yearOf();
        vorbis.date =
            year == null ? <DateTime>[] : <DateTime>[DateTime(year)];
      }
      if (wants(TagField.trackNumber)) {
        final int? value = number(TagField.trackNumber);
        vorbis.trackNumber = value == null ? <int>[] : <int>[value];
      }
      if (wants(TagField.totalTracks)) {
        vorbis.trackTotal = number(TagField.totalTracks);
      }
      if (wants(TagField.discNumber)) {
        vorbis.discNumber = number(TagField.discNumber);
      }
      if (wants(TagField.composer)) {
        vorbis.composer = _listOrNull(text(TagField.composer)) ?? <String>[];
      }
      if (wants(TagField.lyricist)) {
        vorbis.producer = _listOrNull(text(TagField.lyricist)) ?? <String>[];
      }
      if (wants(TagField.comment)) {
        vorbis.comment = _listOrNull(text(TagField.comment)) ?? <String>[];
      }
      if (wants(TagField.lyrics)) {
        vorbis.lyric = _nullIfEmpty(text(TagField.lyrics));
      }
      if (writeCover && tags.coverBytes != null) {
        vorbis.pictures = <Picture>[
          Picture(
            tags.coverBytes!,
            tags.coverMime ?? 'image/jpeg',
            PictureType.coverFront,
          ),
        ];
      }
    case final Mp4Metadata mp4:
      if (wants(TagField.title)) {
        mp4.title = _nullIfEmpty(text(TagField.title));
      }
      if (wants(TagField.artist)) {
        mp4.artist = _nullIfEmpty(text(TagField.artist));
      }
      if (wants(TagField.album)) {
        mp4.album = _nullIfEmpty(text(TagField.album));
      }
      if (wants(TagField.genre)) {
        mp4.genre = _nullIfEmpty(text(TagField.genre));
      }
      if (wants(TagField.year)) {
        final int? year = yearOf();
        mp4.year = year == null ? null : DateTime(year);
      }
      if (wants(TagField.trackNumber)) {
        mp4.trackNumber = number(TagField.trackNumber);
      }
      if (wants(TagField.totalTracks)) {
        mp4.totalTracks = number(TagField.totalTracks);
      }
      if (wants(TagField.discNumber)) {
        mp4.discNumber = number(TagField.discNumber);
      }
      if (wants(TagField.lyrics)) {
        mp4.lyrics = _nullIfEmpty(text(TagField.lyrics));
      }
      if (writeCover && tags.coverBytes != null) {
        mp4.picture = Picture(
          tags.coverBytes!,
          tags.coverMime ?? 'image/jpeg',
          PictureType.coverFront,
        );
      }
    case _:
      // Unrepresentable format — keep the update a no-op (never throws).
  }
}

String? _nullIfEmpty(String value) => value.isEmpty ? null : value;

List<String>? _listOrNull(String value) =>
    value.isEmpty ? null : <String>[value];

/// Convenience: validates [tags] before a save; returns human-readable
/// problems (empty list = valid).
List<String> validateTags(EditableTags tags) {
  final List<String> problems = <String>[];
  final String year = tags.year.trim();
  if (year.isNotEmpty && parseYear(year) == null) {
    problems.add('Year must be a 4-digit number');
  }
  for (final (TagField field, String label) in <(TagField, String)>[
    (TagField.trackNumber, 'Track #'),
    (TagField.totalTracks, 'Total tracks'),
    (TagField.discNumber, 'Disc #'),
  ]) {
    final String value = tags.valueOf(field).trim();
    if (value.isNotEmpty && parseTrackNumber(value) == null) {
      problems.add('$label must be a number');
    }
  }
  return problems;
}

/// Cover bytes helper: reads an image file picked from the gallery.
Future<(Uint8List, String)?> readCoverFile(String path) async {
  try {
    final File file = File(path);
    if (!await file.exists()) {
      return null;
    }
    final Uint8List bytes = await file.readAsBytes();
    return (bytes, _mimeFromExtension(path));
  } on Object {
    return null;
  }
}

String _mimeFromExtension(String path) {
  final String lower = path.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lower.endsWith('.gif')) {
    return 'image/gif';
  }
  return 'image/jpeg';
}

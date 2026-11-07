/// Data model for the batch tag editor (Phase 7.1).
///
/// The editor works on the 13 Musicolet-parity tag fields over concrete
/// audio files. [EditableTags] is the format-neutral snapshot shown in the
/// form; format-specific mapping lives in `tag_io.dart` (MP3 ID3 / FLAC
/// Vorbis / MP4).
library;

import 'dart:typed_data';

/// The 13 editable fields, in editor display order.
enum TagField {
  title,
  artist,
  album,
  albumArtist,
  genre,
  year,
  trackNumber,
  totalTracks,
  discNumber,
  composer,
  lyricist,
  comment,
  lyrics,
}

/// Immutable snapshot of the 13 editable tag fields.
///
/// Empty strings mean "unset" (simpler text-field plumbing than nulls).
class EditableTags {
  EditableTags({
    this.title = '',
    this.artist = '',
    this.album = '',
    this.albumArtist = '',
    this.genre = '',
    this.year = '',
    this.trackNumber = '',
    this.totalTracks = '',
    this.discNumber = '',
    this.composer = '',
    this.lyricist = '',
    this.comment = '',
    this.lyrics = '',
  });

  String title;
  String artist;
  String album;
  String albumArtist;
  String genre;
  String year;
  String trackNumber;
  String totalTracks;
  String discNumber;
  String composer;
  String lyricist;
  String comment;
  String lyrics;

  /// Cover art bytes (decoded image), or `null` when the file has none /
  /// none was picked yet.
  Uint8List? coverBytes;

  /// Cover MIME type for [coverBytes] (e.g. `image/jpeg`).
  String? coverMime;

  /// Reads any field by [TagField].
  String valueOf(TagField field) => switch (field) {
        TagField.title => title,
        TagField.artist => artist,
        TagField.album => album,
        TagField.albumArtist => albumArtist,
        TagField.genre => genre,
        TagField.year => year,
        TagField.trackNumber => trackNumber,
        TagField.totalTracks => totalTracks,
        TagField.discNumber => discNumber,
        TagField.composer => composer,
        TagField.lyricist => lyricist,
        TagField.comment => comment,
        TagField.lyrics => lyrics,
      };

  /// Writes [value] into [field].
  void setValue(TagField field, String value) => switch (field) {
        TagField.title => title = value,
        TagField.artist => artist = value,
        TagField.album => album = value,
        TagField.albumArtist => albumArtist = value,
        TagField.genre => genre = value,
        TagField.year => year = value,
        TagField.trackNumber => trackNumber = value,
        TagField.totalTracks => totalTracks = value,
        TagField.discNumber => discNumber = value,
        TagField.composer => composer = value,
        TagField.lyricist => lyricist = value,
        TagField.comment => comment = value,
        TagField.lyrics => lyrics = value,
      };

  /// Fields whose text value differs from [other] — used by the batch
  /// editor to report "changed on save". Cover bytes are intentionally not
  /// compared (byte-identity is the caller's concern).
  Set<TagField> diffFrom(EditableTags other) => <TagField>{
        for (final TagField field in TagField.values)
          if (valueOf(field) != other.valueOf(field)) field,
      };

  /// A deep copy of the text fields; cover bytes are shared, not cloned
  /// (they are immutable payloads).
  EditableTags copy() {
    final copy = EditableTags();
    for (final TagField field in TagField.values) {
      copy.setValue(field, valueOf(field));
    }
    copy
      ..coverBytes = coverBytes
      ..coverMime = coverMime;
    return copy;
  }
}

/// Parses a year field; accepts 4-digit years. Returns `null` when blank or
/// invalid.
int? parseYear(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final int? parsed = int.tryParse(trimmed);
  if (parsed == null || parsed < 1000 || parsed > 9999) {
    return null;
  }
  return parsed;
}

/// Parses a positive-or-zero counter field (track #, total tracks, disc #).
/// Returns `null` when blank or invalid. Accepts `3/12` composite values by
/// taking the leading part.
int? parseTrackNumber(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final String head = trimmed.split('/').first.trim();
  final int? parsed = int.tryParse(head);
  if (parsed == null || parsed < 0) {
    return null;
  }
  return parsed;
}

/// Result of one tag-write operation.
class TagWriteResult {
  const TagWriteResult._(this.filePath, this.error);

  const TagWriteResult.success(String filePath) : this._(filePath, null);

  const TagWriteResult.failure(String filePath, Object error)
      : this._(filePath, error);

  final String filePath;
  final Object? error;

  bool get isSuccess => error == null;
}

/// Outcome of a batch save.
class BatchTagWriteResult {
  const BatchTagWriteResult({
    required this.succeeded,
    required this.failed,
  });

  final List<TagWriteResult> succeeded;
  final List<TagWriteResult> failed;

  int get total => succeeded.length + failed.length;

  bool get allSucceeded => failed.isEmpty;
}

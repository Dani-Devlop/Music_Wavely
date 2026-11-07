/// Parses tags from a file name (Phase 7.1, "Parse from filename").
///
/// Supported patterns (checked in order, first match wins):
/// 1. `NN. Artist - Title`      → track # NN + artist + title
/// 2. `NN - Artist - Title`     → track # NN + artist + title
/// 3. `NN - Title`              → track # NN + title
/// 4. `Artist - Title`          → artist + title
/// 5. anything else             → title only
///
/// The extension is always stripped. Whitespace around every part is
/// trimmed. Embedded `_-` / `- ` separators with extra spaces collapse
/// naturally because we split on the *last* ` - ` for pattern 4/1/2
/// (artists and titles may contain hyphens — "AC/DC - TNT - Intro" parses
/// as artist `AC/DC - TNT`? No: title is the LAST segment, artist the
/// FIRST, middle segments join back into the artist — the common
/// convention used by Musicolet).
library;

import 'package:wavely/features/tag_editor/data/tag_models.dart';

/// Result of parsing one file name.
class FilenameTags {
  const FilenameTags({
    this.trackNumber,
    this.artist,
    this.title = '',
  });

  /// Leading track number, when the name starts with one.
  final int? trackNumber;

  /// Artist segment, when the name has an `Artist - Title` shape.
  final String? artist;

  /// Title segment (always resolved; falls back to the bare file name).
  final String title;

  /// Applies the parsed values over [tags] without clearing existing
  /// fields: only non-empty parsed values overwrite.
  void applyTo(EditableTags tags) {
    if (trackNumber != null) {
      tags.trackNumber = '$trackNumber';
    }
    final String? parsedArtist = artist;
    if (parsedArtist != null && parsedArtist.isNotEmpty) {
      tags.artist = parsedArtist;
    }
    if (title.isNotEmpty) {
      tags.title = title;
    }
  }
}

/// Parses [fileName] (with or without extension) into [FilenameTags].
FilenameTags parseTagsFromFilename(String fileName) {
  // Strip the extension: everything after the last dot, but only when the
  // stem is non-empty ("hidden. file" keeps its name).
  String stem = fileName;
  final int lastDot = stem.lastIndexOf('.');
  if (lastDot > 0 && lastDot < stem.length - 1) {
    stem = stem.substring(0, lastDot);
  }
  stem = stem.trim();
  if (stem.isEmpty) {
    return const FilenameTags(title: '');
  }

  // Leading track number: "NN." or "NN -" / "NN - ".
  final RegExp leadingNumber = RegExp(r'^(\d{1,4})\s*(?:\.|-)\s*(.*)$');
  int? trackNumber;
  final RegExpMatch? numberMatch = leadingNumber.firstMatch(stem);
  if (numberMatch != null) {
    trackNumber = int.tryParse(numberMatch.group(1)!);
    stem = numberMatch.group(2)!.trim();
  }

  // Artist - Title split on the FIRST ' - ' (titles may contain ' - ';
  // artists rarely do, and this matches Musicolet's behaviour).
  final int separator = stem.indexOf(' - ');
  if (separator > 0 && separator < stem.length - 3) {
    final String artist = stem.substring(0, separator).trim();
    final String title = stem.substring(separator + 3).trim();
    if (artist.isNotEmpty && title.isNotEmpty) {
      return FilenameTags(
        trackNumber: trackNumber,
        artist: artist,
        title: title,
      );
    }
  }

  return FilenameTags(trackNumber: trackNumber, title: stem);
}

/// Convenience: parses [fileName] and returns a fresh [EditableTags] with
/// the parsed values applied.
EditableTags tagsFromFilename(String fileName) {
  final EditableTags tags = EditableTags();
  parseTagsFromFilename(fileName).applyTo(tags);
  return tags;
}

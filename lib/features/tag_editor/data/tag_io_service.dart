/// IO bridge abstraction for the tag editor (Phase 7.1).
///
/// Indirection keeps the controller testable: tests either inject a fake or
/// exercise the real implementation against temporary files.
library;

import 'dart:io';

import 'package:wavely/features/tag_editor/data/tag_io.dart';
import 'package:wavely/features/tag_editor/data/tag_models.dart';

/// Read/write contract used by [TagEditorController].
abstract interface class TagIoService {
  /// Reads the current tags of [file].
  EditableTags read(File file);

  /// Writes [tags] into [file]; see [writeTagsToFile] for the semantics of
  /// [fields] and [writeCover].
  TagWriteResult write(
    File file,
    EditableTags tags, {
    Set<TagField>? fields,
    bool writeCover,
  });
}

/// Production implementation backed by `audio_metadata_reader`.
class AudioMetadataTagIo implements TagIoService {
  const AudioMetadataTagIo();

  @override
  EditableTags read(File file) => readTagsFromFile(file);

  @override
  TagWriteResult write(
    File file,
    EditableTags tags, {
    Set<TagField>? fields,
    bool writeCover = false,
  }) =>
      writeTagsToFile(file, tags, fields: fields, writeCover: writeCover);
}

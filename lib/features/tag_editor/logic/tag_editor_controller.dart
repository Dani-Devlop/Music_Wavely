/// State + controller for the batch tag editor (Phase 7.1).
///
/// Two modes share one controller:
/// - **single** (one file): every keystroke edits that file's draft.
/// - **batch** (multiple files): edits land in [TagEditorState.batchDraft];
///   on save, only the checked [TagEditorState.batchFields] are pushed to
///   every file, so untouched fields keep their per-file values.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/legacy.dart';
import 'package:wavely/features/tag_editor/data/filename_tag_parser.dart';
import 'package:wavely/features/tag_editor/data/tag_io_service.dart';
import 'package:wavely/features/tag_editor/data/tag_models.dart';

/// One file loaded into the editor.
class TagEditorEntry {
  TagEditorEntry({
    required this.filePath,
    required this.fileName,
    this.original,
    this.loadError,
  });

  final String filePath;
  final String fileName;

  /// Snapshot as loaded from disk; `null` until loaded (or when the load
  /// failed, see [loadError]).
  EditableTags? original;

  /// Working copy the user edits.
  EditableTags? current;

  /// Load failure message (per-file failures never abort the batch).
  String? loadError;

  bool get isLoaded => original != null;

  /// Fields edited relative to [original].
  Set<TagField> changes() {
    final EditableTags? orig = original;
    final EditableTags? cur = current;
    if (orig == null || cur == null) {
      return const <TagField>{};
    }
    return cur.diffFrom(orig);
  }

  bool get hasCoverChange =>
      current?.coverBytes != null &&
      current?.coverBytes != original?.coverBytes;
}

/// Immutable-ish editor state (mutated through copyWith).
class TagEditorState {
  const TagEditorState({
    this.entries = const <TagEditorEntry>[],
    this.selectedIndex = 0,
    this.batchDraft,
    this.batchFields = const <TagField>{},
    this.saving = false,
    this.lastResult,
  });

  final List<TagEditorEntry> entries;
  final int selectedIndex;
  final EditableTags? batchDraft;

  /// Fields the batch save will push to every file.
  final Set<TagField> batchFields;

  final bool saving;
  final BatchTagWriteResult? lastResult;

  bool get isBatch => entries.length > 1;

  TagEditorEntry? get selected =>
      entries.isEmpty || selectedIndex >= entries.length
          ? null
          : entries[selectedIndex];

  TagEditorState copyWith({
    List<TagEditorEntry>? entries,
    int? selectedIndex,
    EditableTags? batchDraft,
    Set<TagField>? batchFields,
    bool? saving,
    BatchTagWriteResult? lastResult,
    bool clearResult = false,
  }) =>
      TagEditorState(
        entries: entries ?? this.entries,
        selectedIndex: selectedIndex ?? this.selectedIndex,
        batchDraft: batchDraft ?? this.batchDraft,
        batchFields: batchFields ?? this.batchFields,
        saving: saving ?? this.saving,
        lastResult: clearResult ? null : (lastResult ?? this.lastResult),
      );
}

/// Drives the tag editor screen.
class TagEditorController extends StateNotifier<TagEditorState> {
  TagEditorController({TagIoService? io}) : _io = io ?? const AudioMetadataTagIo(), super(const TagEditorState());

  final TagIoService _io;

  /// Loads [filePaths] into the editor (per-file read failures degrade to
  /// an error entry, never an exception).
  Future<void> load(List<String> filePaths) async {
    final List<TagEditorEntry> entries = <TagEditorEntry>[
      for (final String path in filePaths)
        TagEditorEntry(
          filePath: path,
          fileName: path.split(Platform.pathSeparator).last,
        ),
    ];
    state = TagEditorState(entries: entries);
    for (final TagEditorEntry entry in entries) {
      try {
        final EditableTags tags = _io.read(File(entry.filePath));
        entry
          ..original = tags
          ..current = tags.copy();
      } on Object catch (error) {
        entry.loadError = error.toString();
      }
      // Publish progressively so the UI can stream entries in.
      state = state.copyWith(entries: List<TagEditorEntry>.of(state.entries));
    }
    _syncBatchDraft();
  }

  void select(int index) {
    if (index < 0 || index >= state.entries.length) {
      return;
    }
    state = state.copyWith(selectedIndex: index);
  }

  /// Updates a field on the active target (selected file draft in single
  /// mode, the batch draft in batch mode).
  void updateField(TagField field, String value) {
    if (state.isBatch) {
      final EditableTags draft =
          state.batchDraft ?? EditableTags();
      draft.setValue(field, value);
      state = state.copyWith(batchDraft: draft);
      return;
    }
    final TagEditorEntry? entry = state.selected;
    final EditableTags? current = entry?.current;
    if (current == null) {
      return;
    }
    current.setValue(field, value);
    state = state.copyWith(entries: List<TagEditorEntry>.of(state.entries));
  }

  /// Toggles whether [field] participates in the batch save.
  void toggleBatchField(TagField field) {
    final Set<TagField> next = <TagField>{...state.batchFields};
    if (!next.remove(field)) {
      next.add(field);
    }
    state = state.copyWith(batchFields: next);
  }

  /// Applies "parse tags from filename" to every entry (or just the
  /// selected one when [onlySelected] is true).
  void parseFromFilenames({bool onlySelected = false}) {
    final List<TagEditorEntry> entries =
        List<TagEditorEntry>.of(state.entries);
    for (var i = 0; i < entries.length; i++) {
      if (onlySelected && i != state.selectedIndex) {
        continue;
      }
      final TagEditorEntry entry = entries[i];
      final EditableTags? current = entry.current;
      if (current == null) {
        continue;
      }
      parseTagsFromFilename(entry.fileName).applyTo(current);
    }
    state = state.copyWith(entries: entries);
    _syncBatchDraft();
  }

  /// Replaces the cover art: single mode sets it on the selected file,
  /// batch mode on the draft (applied to every file on save).
  void setCover(Uint8List bytes, String mime) {
    if (state.isBatch) {
      final EditableTags draft =
          state.batchDraft ?? EditableTags();
      draft
        ..coverBytes = bytes
        ..coverMime = mime;
      state = state.copyWith(batchDraft: draft);
      return;
    }
    final TagEditorEntry? entry = state.selected;
    final EditableTags? current = entry?.current;
    if (current == null) {
      return;
    }
    current
      ..coverBytes = bytes
      ..coverMime = mime;
    state = state.copyWith(entries: List<TagEditorEntry>.of(state.entries));
  }

  /// Saves all pending edits.
  ///
  /// - Single mode: writes every changed field of the selected file.
  /// - Batch mode: writes the checked batch fields (and the draft cover,
  ///   when set) to every loaded file.
  Future<BatchTagWriteResult> save() async {
    final List<TagWriteResult> ok = <TagWriteResult>[];
    final List<TagWriteResult> failed = <TagWriteResult>[];

    state = state.copyWith(saving: true, clearResult: true);

    if (state.isBatch) {
      final EditableTags? draft = state.batchDraft;
      final Set<TagField> fields = state.batchFields;
      final bool writeCover = draft?.coverBytes != null;
      for (final TagEditorEntry entry in state.entries) {
        final EditableTags? current = entry.current;
        if (current == null || (fields.isEmpty && !writeCover)) {
          continue;
        }
        // Batch semantics: the per-file draft keeps unchecked fields; the
        // batch draft supplies the checked fields + the shared cover.
        final EditableTags merged = current.copy();
        if (draft != null) {
          for (final TagField field in fields) {
            merged.setValue(field, draft.valueOf(field));
          }
          if (writeCover) {
            merged
              ..coverBytes = draft.coverBytes
              ..coverMime = draft.coverMime;
          }
        }
        final TagWriteResult result = _io.write(
          File(entry.filePath),
          merged,
          fields: fields,
          writeCover: writeCover,
        );
        _record(result, ok, failed);
      }
    } else {
      final TagEditorEntry? entry = state.selected;
      final EditableTags? current = entry?.current;
      if (entry != null && current != null) {
        final TagWriteResult result = _io.write(
          File(entry.filePath),
          current,
          writeCover: entry.hasCoverChange,
        );
        _record(result, ok, failed);
        if (result.isSuccess) {
          entry
            ..original = current.copy()
            ..current = current.copy();
        }
      }
    }

    final BatchTagWriteResult result = BatchTagWriteResult(
      succeeded: ok,
      failed: failed,
    );
    state = state.copyWith(saving: false, lastResult: result);
    return result;
  }

  void _record(
    TagWriteResult result,
    List<TagWriteResult> ok,
    List<TagWriteResult> failed,
  ) =>
      result.isSuccess ? ok.add(result) : failed.add(result);

  /// Batch draft mirrors the first loaded file so the form starts from a
  /// meaningful state.
  void _syncBatchDraft() {
    if (!state.isBatch) {
      return;
    }
    final TagEditorEntry? first = state.entries.firstWhere(
      (TagEditorEntry entry) => entry.current != null,
      orElse: () => TagEditorEntry(filePath: '', fileName: ''),
    );
    state = state.copyWith(
      batchDraft: first?.current?.copy() ?? state.batchDraft,
    );
  }
}

/// Manual provider (one editor screen instance at a time).
final tagEditorControllerProvider =
    StateNotifierProvider.autoDispose<TagEditorController, TagEditorState>(
  (ref) => TagEditorController(),
);

/// Batch tag editor screen (Phase 7.1).
///
/// 13-field form (Title, Artist, Album, Album Artist, Genre, Year,
/// Track #, Total tracks, Disc #, Composer, Lyricist, Comment, Lyrics) with:
/// - single-file editing when one track is passed,
/// - batch mode for multiple tracks (checkbox per field decides what gets
///   pushed to every file),
/// - "parse tags from filename" (`Artist - Title.mp3`, `NN. Artist - ...`),
/// - cover-art replacement from the device gallery (single + batch).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/features/tag_editor/data/tag_io.dart' as tag_io;
import 'package:wavely/features/tag_editor/data/tag_models.dart';
import 'package:wavely/features/tag_editor/logic/tag_editor_controller.dart';

/// Route path used by the library multi-select bar.
const String kTagEditorRoute = '/library/tag-editor';

/// Opens the gallery picker; injectable for widget tests.
typedef CoverImagePicker = Future<String?> Function();

/// Default gallery picker (file_picker, images only).
Future<String?> pickCoverImageFromGallery() async {
  final List<PlatformFile> files = await FilePicker.pickFiles(
    type: FileType.image,
    compressionQuality: 0,
  );
  return files.firstOrNull?.path;
}

/// The 13 fields in display order with their labels.
const List<(TagField, String)> kTagEditorFields = <(TagField, String)>[
  (TagField.title, 'Title'),
  (TagField.artist, 'Artist'),
  (TagField.album, 'Album'),
  (TagField.albumArtist, 'Album Artist'),
  (TagField.genre, 'Genre'),
  (TagField.year, 'Year'),
  (TagField.trackNumber, 'Track #'),
  (TagField.totalTracks, 'Total tracks'),
  (TagField.discNumber, 'Disc #'),
  (TagField.composer, 'Composer'),
  (TagField.lyricist, 'Lyricist'),
  (TagField.comment, 'Comment'),
  (TagField.lyrics, 'Lyrics'),
];

/// Tag editor screen. [filePaths] drives single vs batch mode; [pickCover]
/// is injectable for tests.
class TagEditorScreen extends ConsumerStatefulWidget {
  const TagEditorScreen({
    required this.filePaths,
    this.pickCover = pickCoverImageFromGallery,
    super.key,
  });

  final List<String> filePaths;
  final CoverImagePicker pickCover;

  @override
  ConsumerState<TagEditorScreen> createState() => _TagEditorScreenState();
}

class _TagEditorScreenState extends ConsumerState<TagEditorScreen> {
  @override
  void initState() {
    super.initState();
    // Fire-and-forget: the screen shows per-entry load state.
    unawaited(
      ref.read(tagEditorControllerProvider.notifier).load(widget.filePaths),
    );
  }

  Future<void> _replaceCover() async {
    final String? path = await widget.pickCover();
    if (path == null || !mounted) {
      return;
    }
    final (Uint8List, String)? cover = await tag_io.readCoverFile(path);
    if (cover == null || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read the picked image')),
      );
      return;
    }
    ref
        .read(tagEditorControllerProvider.notifier)
        .setCover(cover.$1, cover.$2);
  }

  Future<void> _save() async {
    final TagEditorController controller =
        ref.read(tagEditorControllerProvider.notifier);
    final BatchTagWriteResult result = await controller.save();
    if (!mounted) {
      return;
    }
    final String message = result.allSucceeded
        ? 'Saved ${result.succeeded.length} '
            '${result.succeeded.length == 1 ? 'file' : 'files'}'
        : 'Saved ${result.succeeded.length}, failed '
            '${result.failed.length}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    if (result.allSucceeded) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final TagEditorState state = ref.watch(tagEditorControllerProvider);
    final TagEditorController controller =
        ref.read(tagEditorControllerProvider.notifier);
    final bool isBatch = state.isBatch;
    final TagEditorEntry? selected = state.selected;

    return Scaffold(
      key: const ValueKey<String>('tag-editor-screen'),
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        title: Text(
          isBatch
              ? 'Edit Tags — ${state.entries.length} files'
              : 'Edit Tags',
          style: WavelyTypography.title20(color: colors.textPrimary),
        ),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('tag-editor-parse-filename'),
            tooltip: 'Parse from filename',
            icon: const Icon(Icons.text_fields_rounded),
            onPressed: () => controller.parseFromFilenames(),
          ),
          IconButton(
            key: const ValueKey<String>('tag-editor-replace-cover'),
            tooltip: 'Replace cover',
            icon: const Icon(Icons.image_outlined),
            onPressed: _replaceCover,
          ),
          IconButton(
            key: const ValueKey<String>('tag-editor-save'),
            tooltip: 'Save',
            icon: state.saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            onPressed: state.saving ? null : _save,
          ),
        ],
      ),
      body: state.entries.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                if (isBatch) _BatchFileStrip(state: state, onTap: controller.select),
                Expanded(
                  child: isBatch
                      ? _BatchForm(state: state, controller: controller)
                      : _SingleForm(
                          state: state,
                          selected: selected,
                          controller: controller,
                        ),
                ),
              ],
            ),
    );
  }
}

/// Horizontal file strip shown in batch mode.
class _BatchFileStrip extends StatelessWidget {
  const _BatchFileStrip({required this.state, required this.onTap});

  final TagEditorState state;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.xs,
        ),
        itemCount: state.entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: Spacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final TagEditorEntry entry = state.entries[index];
          final bool active = index == state.selectedIndex;
          return ChoiceChip(
            key: ValueKey<String>('tag-editor-file-$index'),
            label: Text(entry.fileName),
            selected: active,
            onSelected: (_) => onTap(index),
            labelStyle: WavelyTypography.caption12(
              color: active ? colors.bgBase : colors.textSecondary,
            ),
          );
        },
      ),
    );
  }
}

/// Batch form: per-field checkbox + shared draft value.
class _BatchForm extends StatelessWidget {
  const _BatchForm({required this.state, required this.controller});

  final TagEditorState state;
  final TagEditorController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final EditableTags? draft = state.batchDraft;
    if (draft == null) {
      return Center(
        child: Text(
          'No readable files in the selection',
          style: WavelyTypography.body14(color: colors.textSecondary),
        ),
      );
    }
    return ListView(
      key: const ValueKey<String>('tag-editor-batch-form'),
      padding: const EdgeInsets.all(Spacing.lg),
      children: <Widget>[
        Text(
          'Check a field to overwrite it on every selected file',
          style: WavelyTypography.caption12(color: colors.textSecondary),
        ),
        const SizedBox(height: Spacing.md),
        for (final (TagField, String) field in kTagEditorFields)
          _BatchFieldRow(
            field: field.$1,
            label: field.$2,
            value: draft.valueOf(field.$1),
            checked: state.batchFields.contains(field.$1),
            onChecked: (bool? value) =>
                controller.toggleBatchField(field.$1),
            onChanged: (String value) => controller.updateField(field.$1, value),
          ),
        const SizedBox(height: Spacing.lg),
      ],
    );
  }
}

class _BatchFieldRow extends StatelessWidget {
  const _BatchFieldRow({
    required this.field,
    required this.label,
    required this.value,
    required this.checked,
    required this.onChecked,
    required this.onChanged,
  });

  final TagField field;
  final String label;
  final String value;
  final bool checked;
  final ValueChanged<bool?> onChecked;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool multiline = field == TagField.lyrics;
    return Row(
      crossAxisAlignment:
          multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 32,
          child: Checkbox(
            key: ValueKey<String>('tag-editor-batch-${field.name}'),
            value: checked,
            onChanged: onChecked,
          ),
        ),
        Expanded(
          child: _TagTextField(
            key: ValueKey<String>('tag-editor-field-${field.name}'),
            label: label,
            value: value,
            multiline: multiline,
            enabled: checked,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Single-file form: plain 13-field editor.
class _SingleForm extends StatelessWidget {
  const _SingleForm({
    required this.state,
    required this.selected,
    required this.controller,
  });

  final TagEditorState state;
  final TagEditorEntry? selected;
  final TagEditorController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final EditableTags? current = selected?.current;
    if (current == null) {
      return Center(
        child: Text(
          selected?.loadError ?? 'Loading…',
          style: WavelyTypography.body14(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView(
      key: const ValueKey<String>('tag-editor-single-form'),
      padding: const EdgeInsets.all(Spacing.lg),
      children: <Widget>[
        Text(
          selected!.fileName,
          style: WavelyTypography.caption12(color: colors.textSecondary),
        ),
        const SizedBox(height: Spacing.md),
        for (final (TagField, String) field in kTagEditorFields)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: _TagTextField(
              key: ValueKey<String>('tag-editor-field-${field.$1.name}'),
              label: field.$2,
              value: current.valueOf(field.$1),
              multiline: field.$1 == TagField.lyrics,
              enabled: true,
              onChanged: (String value) =>
                  controller.updateField(field.$1, value),
            ),
          ),
        const SizedBox(height: Spacing.lg),
      ],
    );
  }
}

class _TagTextField extends StatefulWidget {
  const _TagTextField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.multiline,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String value;
  final bool enabled;
  final bool multiline;
  final ValueChanged<String> onChanged;

  @override
  State<_TagTextField> createState() => _TagTextFieldState();
}

class _TagTextFieldState extends State<_TagTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  /// Last value this field pushed upstream; typing must not be echoed
  /// back, but external resets (parse-from-filename, batch draft swap)
  /// flow in through [didUpdateWidget].
  String? _lastPushed;

  @override
  void didUpdateWidget(_TagTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text && widget.value != _lastPushed) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      maxLines: widget.multiline ? 4 : 1,
      minLines: widget.multiline ? 3 : 1,
      style: WavelyTypography.body14(color: colors.textPrimary),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: WavelyTypography.caption12(color: colors.textSecondary),
        border: OutlineInputBorder(borderRadius: AppRadii.bMd),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
      ),
      onChanged: (String value) {
        _lastPushed = value;
        widget.onChanged(value);
      },
    );
  }
}

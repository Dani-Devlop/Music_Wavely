/// Confirmation dialogs + menus for the library file operations
/// (Phase 7.3) and the entries that open the tag editor / audio cutter.
///
/// Every destructive or moving operation requires an explicit confirmation
/// dialog (Musicolet parity); dialogs return what the caller needs
/// (new name / target directory / confirmation) or `null` on cancel.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/features/library/data/file_operations/file_operations.dart';
import 'package:wavely/features/library/data/file_operations/file_operations_provider.dart';

/// Shows the file-operations bottom sheet for [paths]; returns the
/// [FileOpBatchResult] after the user confirmed and the op ran, or `null`
/// when dismissed.
Future<FileOpBatchResult?> showFileOpsSheet(
  BuildContext context,
  WidgetRef ref,
  List<String> paths,
) async {
  if (paths.isEmpty) {
    return null;
  }
  final FileOpKind? kind = await showModalBottomSheet<FileOpKind>(
    context: context,
    builder: (BuildContext sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final FileOpKind kind in FileOpKind.values)
            ListTile(
              key: ValueKey<String>('file-op-${kind.name}'),
              leading: Icon(switch (kind) {
                FileOpKind.rename => Icons.drive_file_rename_outline,
                FileOpKind.move => Icons.drive_file_move_outline,
                FileOpKind.copy => Icons.copy_rounded,
                FileOpKind.delete => Icons.delete_forever_outlined,
              }),
              title: Text(kind.label),
              subtitle: kind == FileOpKind.delete
                  ? const Text('Deletes the audio files from disk')
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(kind),
            ),
        ],
      ),
    ),
  );
  if (kind == null || !context.mounted) {
    return null;
  }
  final FileOperations ops = ref.read(fileOperationsProvider);

  switch (kind) {
    case FileOpKind.rename:
      final String? pattern = await _promptRenamePattern(context, paths);
      if (pattern == null || !context.mounted) {
        return null;
      }
      if (paths.length == 1) {
        // Single file: the pattern is the plain new name.
        return runBatch(ops, FileOpKind.rename, paths, newName: pattern);
      }
      return renamePattern(ops, paths, pattern);
    case FileOpKind.move:
    case FileOpKind.copy:
      final String? dir = await _promptTargetDirectory(context);
      if (dir == null || !context.mounted) {
        return null;
      }
      final bool? confirmed = await _confirm(
        context,
        title: kind == FileOpKind.move ? 'Move files?' : 'Copy files?',
        body: '${paths.length} '
            '${paths.length == 1 ? 'file' : 'files'} will be '
            '${kind == FileOpKind.move ? 'moved' : 'copied'} to:\n$dir',
        confirmLabel: kind.label,
      );
      if (confirmed != true || !context.mounted) {
        return null;
      }
      return runBatch(
        ops,
        kind,
        paths,
        targetDirectory: dir,
      );
    case FileOpKind.delete:
      final bool? confirmed = await _confirm(
        context,
        title: 'Delete files permanently?',
        body: '${paths.length} '
            '${paths.length == 1 ? 'file' : 'files'} will be deleted '
            'from disk. This cannot be undone.',
        confirmLabel: 'Delete',
        danger: true,
      );
      if (confirmed != true || !context.mounted) {
        return null;
      }
      return runBatch(ops, FileOpKind.delete, paths);
  }
}

/// Rename dialog: single file → plain name; multiple → pattern with %n/%t.
Future<String?> _promptRenamePattern(
  BuildContext context,
  List<String> paths,
) async {
  final TextEditingController ctrl = TextEditingController(
    text: paths.length == 1 ? '' : 'Track %n',
  );
  final String? result = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(
        paths.length == 1 ? 'Rename file' : 'Rename ${paths.length} files',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            key: const ValueKey<String>('file-op-rename-field'),
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: paths.length == 1
                  ? 'New name (without extension)'
                  : 'Name pattern',
              helperText: paths.length == 1
                  ? 'The file extension is kept'
                  : '%n = track number, %t = original name',
            ),
            onSubmitted: (String value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(ctrl.text.trim()),
          child: const Text('Rename'),
        ),
      ],
    ),
  );
  return (result == null || result.isEmpty) ? null : result;
}

/// Directory picker (file_picker getDirectoryPath with a manual-entry
/// fallback for environments without a native picker).
Future<String?> _promptTargetDirectory(BuildContext context) async {
  try {
    final String? picked = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose target folder',
    );
    if (picked != null) {
      return picked;
    }
  } on Object {
    // Fall through to manual entry.
  }
  if (!context.mounted) {
    return null;
  }
  final TextEditingController ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('Target folder'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Absolute folder path',
        ),
        onSubmitted: (String value) =>
            Navigator.of(dialogContext).pop(value.trim()),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(ctrl.text.trim()),
          child: const Text('Use folder'),
        ),
      ],
    ),
  );
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool danger = false,
}) {
  final colors = context.wavelyColors;
  return showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('file-op-confirm'),
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.bgBase,
                )
              : null,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

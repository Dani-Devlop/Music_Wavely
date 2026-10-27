import 'dart:io';

import 'package:flutter/widgets.dart';

/// Native implementation: resolves [path] to a file-backed image provider
/// (null when there is no path or the file is gone).
ImageProvider<Object>? wavelyCoverProvider(String? path) {
  if (path == null) {
    return null;
  }
  final file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  return FileImage(file);
}

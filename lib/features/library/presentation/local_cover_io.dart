import 'dart:io';

import 'package:flutter/material.dart';

/// Native implementation: loads [path] as a file-backed image provider
/// (null when there is no path or the file was deleted).
ImageProvider<Object>? localCoverProvider(String? path) {
  if (path == null) {
    return null;
  }
  final file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  return FileImage(file);
}

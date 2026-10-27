import 'package:flutter/widgets.dart';

/// Web implementation: the browser sandbox cannot read local file paths, so
/// covers resolve to null and the UI falls back to its placeholder.
ImageProvider<Object>? wavelyCoverProvider(String? path) => null;

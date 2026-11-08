import 'dart:io';
import 'dart:typed_data';

/// Reads cover image bytes for the adaptive-accent extractor (native arm).
Future<Uint8List?> readCoverBytes(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    return await file.readAsBytes();
  } on Object {
    return null;
  }
}

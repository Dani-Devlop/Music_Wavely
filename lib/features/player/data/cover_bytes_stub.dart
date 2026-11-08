import 'dart:typed_data';

/// Web arm of the cover byte reader — local cover files do not exist on
/// the web target (covers resolve through network image providers), so the
/// adaptive-accent extractor degrades to null there.
Future<Uint8List?> readCoverBytes(String path) async => null;

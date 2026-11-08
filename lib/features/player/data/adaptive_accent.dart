import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:wavely/features/player/data/cover_bytes_io.dart'
    if (dart.library.js_interop) 'package:wavely/features/player/data/cover_bytes_stub.dart'
    show readCoverBytes;

/// Phase 10.1: derives an accent color from the album art.
///
/// Pure dart:ui pipeline (no palette dependency): decode a small bitmap,
/// sample the RGBA buffer, drop transparent / near-gray / extreme-luminance
/// pixels, then average weighted by saturation so a dominant tinted region
/// wins over the background.
class AdaptiveAccentExtractor {
  const AdaptiveAccentExtractor._();

  /// Decode cap: a 48px bitmap keeps the byte loop trivially cheap.
  static const int _sampleSize = 48;

  /// Saturation floor — below this a pixel counts as gray and is ignored.
  static const double _minSaturation = 0.18;

  /// Luminance window — extremely dark/bright pixels are excluded so
  /// black vinyl frames and white margins do not skew the accent.
  static const double _minLightness = 0.2;
  static const double _maxLightness = 0.92;

  /// Extracts an accent [Color] from an encoded image file, or null when
  /// decoding fails / no eligible pixels exist.
  static Future<Color?> fromFile(String? path) async {
    if (path == null || path.isEmpty) {
      return null;
    }
    try {
      final bytes = await readCoverBytes(path);
      if (bytes == null || bytes.isEmpty) {
        return null;
      }
      return await fromBytes(bytes);
    } on Object {
      return null;
    }
  }

  /// Extracts the accent from encoded image bytes (PNG/JPEG — whatever
  /// dart:ui can decode). Public for tests.
  static Future<Color?> fromBytes(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: _sampleSize,
        targetHeight: _sampleSize,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      codec.dispose();
      if (data == null) {
        return null;
      }
      return fromRawRgba(data.buffer.asUint8List());
    } on Object {
      return null;
    }
  }

  /// Pure pixel-average over an RGBA buffer (public for tests).
  static Color? fromRawRgba(Uint8List rgba) {
    final pixelCount = rgba.length ~/ 4;
    if (pixelCount == 0) {
      return null;
    }
    double rSum = 0, gSum = 0, bSum = 0;
    double weightSum = 0;
    for (var i = 0; i < rgba.length; i += 4) {
      final a = rgba[i + 3];
      if (a < 255 ~/ 2) {
        continue; // transparent
      }
      final color = Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]);
      final hsl = HSLColor.fromColor(color);
      if (hsl.saturation < _minSaturation) {
        continue; // gray
      }
      if (hsl.lightness < _minLightness || hsl.lightness > _maxLightness) {
        continue; // too dark / too bright
      }
      // Weight by saturation: strongly tinted pixels dominate.
      final w = 0.5 + hsl.saturation;
      rSum += color.red * w;
      gSum += color.green * w;
      bSum += color.blue * w;
      weightSum += w;
    }
    if (weightSum == 0) {
      return null;
    }
    final r = (rSum / weightSum).round().clamp(0, 255);
    final g = (gSum / weightSum).round().clamp(0, 255);
    final b = (bSum / weightSum).round().clamp(0, 255);
    return Color.fromARGB(255, r, g, b);
  }
}

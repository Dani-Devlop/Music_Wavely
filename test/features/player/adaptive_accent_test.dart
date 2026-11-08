// Phase 10.1 — AdaptiveAccentExtractor (album-art accent extraction).
//
// The pixel-average pipeline is tested directly on raw RGBA buffers; the
// codec path is exercised with a PNG rendered in-test through dart:ui.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/player/data/adaptive_accent.dart';

Future<Uint8List> _pngBytes(List<Color> pixels, int width) async {
  // Render a solid-color strip and snapshot it as PNG bytes.
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint();
  for (var x = 0; x < width; x++) {
    paint.color = pixels[x % pixels.length];
    canvas.drawRect(Rect.fromLTWH(x.toDouble(), 0, 1, 4), paint);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, 4);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdaptiveAccentExtractor.fromRawRgba', () {
    test('averages a saturated red field into a red accent', () {
      final rgba = <int>[];
      for (var i = 0; i < 64; i++) {
        rgba.addAll(<int>[0xE4, 0x4B, 0x3C, 0xFF]);
      }
      final accent = AdaptiveAccentExtractor.fromRawRgba(
        Uint8List.fromList(rgba),
      );
      expect(accent, isNotNull);
      expect(accent!.red, greaterThan(accent.blue));
      expect(accent.red, greaterThan(accent.green));
    });

    test('gray-only buffers yield null (no eligible pixels)', () {
      final rgba = <int>[];
      for (var i = 0; i < 16; i++) {
        rgba.addAll(<int>[0x80, 0x80, 0x80, 0xFF]);
      }
      expect(
        AdaptiveAccentExtractor.fromRawRgba(Uint8List.fromList(rgba)),
        isNull,
      );
    });

    test('near-black and near-white pixels are excluded', () {
      final rgba = <int>[
        0x0A, 0x0A, 0x0A, 0xFF, // too dark
        0xFC, 0xFC, 0xFC, 0xFF, // too bright
      ];
      expect(
        AdaptiveAccentExtractor.fromRawRgba(Uint8List.fromList(rgba)),
        isNull,
      );
    });

    test('transparent pixels are ignored', () {
      final rgba = <int>[0xE4, 0x4B, 0x3C, 0x00];
      expect(
        AdaptiveAccentExtractor.fromRawRgba(Uint8List.fromList(rgba)),
        isNull,
      );
    });

    test('empty buffers yield null', () {
      expect(
        AdaptiveAccentExtractor.fromRawRgba(Uint8List.fromList(<int>[])),
        isNull,
      );
    });
  });

  group('AdaptiveAccentExtractor.fromBytes (codec path)', () {
    test('decodes a rendered PNG into an accent', () async {
      final bytes = await _pngBytes(
        <Color>[const Color(0xFF3C64E4)],
        16,
      );
      final accent = await AdaptiveAccentExtractor.fromBytes(bytes);
      expect(accent, isNotNull);
      // Blue-dominant source art produces a blue-dominant accent.
      expect(accent!.blue, greaterThan(accent.red));
    });

    test('corrupt bytes degrade to null', () async {
      final accent = await AdaptiveAccentExtractor.fromBytes(
        Uint8List.fromList(<int>[0, 1, 2, 3]),
      );
      expect(accent, isNull);
    });
  });
}

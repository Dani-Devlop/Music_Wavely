/// Tests for the Phase 7.2 waveform peak computation.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/audio_cutter/data/waveform_peaks.dart';

/// Builds little-endian s16le PCM from sample values.
Uint8List pcmFromSamples(List<int> samples) {
  final ByteData data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  group('WaveformPeaks.fromPcmBytes', () {
    test('produces the requested bucket count', () {
      final WaveformPeaks peaks = WaveformPeaks.fromPcmBytes(
        pcmFromSamples(List<int>.filled(1000, 100)),
        bucketCount: 10,
      );
      expect(peaks.length, 10);
    });

    test('empty input yields all-zero peaks', () {
      final WaveformPeaks peaks = WaveformPeaks.fromPcmBytes(
        Uint8List(0),
        bucketCount: 8,
      );
      expect(peaks.length, 8);
      expect(peaks.maxPeak, 0);
      expect(peaks.durationMs, 0);
    });

    test('peak amplitude normalizes to 0..1 and scales to full', () {
      // One loud bucket (max) and one quiet bucket.
      final List<int> samples = <int>[
        ...List<int>.filled(100, 16000), // bucket 0-ish
        ...List<int>.filled(100, 4000), // quieter
      ];
      final WaveformPeaks peaks = WaveformPeaks.fromPcmBytes(
        pcmFromSamples(samples),
        bucketCount: 2,
      );
      expect(peaks.maxPeak, closeTo(1.0, 0.001));
      expect(peaks.peakAt(1), lessThan(peaks.peakAt(0)));
      expect(peaks.peakAt(1), greaterThan(0));
    });

    test('duration derives from sample count and rate', () {
      final WaveformPeaks peaks = WaveformPeaks.fromPcmBytes(
        pcmFromSamples(List<int>.filled(8000, 1)),
        bucketCount: 4,
        sampleRate: 8000,
      );
      expect(peaks.durationMs, 1000);
    });

    test('negative samples count toward the peak (absolute)', () {
      final WaveformPeaks peaks = WaveformPeaks.fromPcmBytes(
        pcmFromSamples(List<int>.filled(100, -32000)),
        bucketCount: 1,
      );
      expect(peaks.maxPeak, closeTo(1.0, 0.001));
    });
  });

  group('downsample', () {
    test('merges buckets by max', () {
      final WaveformPeaks peaks = WaveformPeaks.fromPcmBytes(
        pcmFromSamples(<int>[
          20000, 0, 0, 0, // bucket 0 loud
          0, 0, 0, 0, // bucket 1 silent
        ]),
        bucketCount: 2,
      );
      final WaveformPeaks merged = peaks.downsample(1);
      expect(merged.length, 1);
      expect(merged.peakAt(0), closeTo(peaks.peakAt(0), 0.001));
    });

    test('no-op when target >= length', () {
      final WaveformPeaks peaks = WaveformPeaks.fromPcmBytes(
        pcmFromSamples(List<int>.filled(10, 100)),
        bucketCount: 4,
      );
      expect(identical(peaks.downsample(4), peaks), isTrue);
    });
  });
}

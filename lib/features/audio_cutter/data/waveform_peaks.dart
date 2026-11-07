/// Waveform peak computation from decoded PCM bytes (Phase 7.2).
///
/// The cutter decodes audio to mono 16-bit PCM (via FFmpeg when available)
/// and reduces it to a fixed-width peak envelope for the waveform canvas.
/// [WaveformPeaks.fromPcmBytes] is pure Dart and unit-tested directly.
library;

import 'dart:typed_data';

/// Peak envelope over one audio file.
class WaveformPeaks {
  WaveformPeaks._(this._peaks, this.sampleRate, this.durationMs);

  final Float32List _peaks;

  /// Sample rate of the decoded PCM (informational).
  final int sampleRate;

  /// Duration the PCM bytes represent (ms).
  final int durationMs;

  /// Bucket count.
  int get length => _peaks.length;

  /// Peak amplitude at [index] in `0..1`.
  double peakAt(int index) {
    if (index < 0 || index >= _peaks.length) {
      return 0;
    }
    return _peaks[index];
  }

  /// Normalized maximum (for canvas auto-scale).
  double get maxPeak {
    double max = 0;
    for (var i = 0; i < _peaks.length; i++) {
      if (_peaks[i] > max) {
        max = _peaks[i];
      }
    }
    return max;
  }

  /// Computes [bucketCount] peaks from little-endian signed 16-bit mono PCM.
  ///
  /// Every bucket takes the max absolute sample of its slice; the result is
  /// normalized by 32768. Trailing partial buckets are averaged by
  /// position, so [bucketCount] is always produced (empty input yields all
  /// zeros).
  static WaveformPeaks fromPcmBytes(
    Uint8List pcmBytes, {
    required int bucketCount,
    int sampleRate = 8000,
  }) {
    final Float32List peaks = Float32List(bucketCount);
    if (bucketCount <= 0 || pcmBytes.isEmpty) {
      return WaveformPeaks._(peaks, sampleRate, 0);
    }
    // 16-bit samples → 2 bytes each.
    final ByteData view = ByteData.sublistView(pcmBytes);
    final int sampleCount = pcmBytes.length ~/ 2;
    if (sampleCount == 0) {
      return WaveformPeaks._(peaks, sampleRate, 0);
    }
    final double samplesPerBucket = sampleCount / bucketCount;
    var bucket = 0;
    var bucketEnd = samplesPerBucket;
    double max = 0;
    for (var s = 0; s < sampleCount; s++) {
      while (s >= bucketEnd && bucket < bucketCount - 1) {
        bucket++;
        bucketEnd += samplesPerBucket;
      }
      final int value = view.getInt16(s * 2, Endian.little);
      final double amplitude = (value.abs()) / 32768.0;
      if (amplitude > peaks[bucket]) {
        peaks[bucket] = amplitude;
      }
      if (amplitude > max) {
        max = amplitude;
      }
    }
    // Normalize to the loudest bucket so quiet tracks still draw fully.
    if (max > 0 && max < 1) {
      final double scale = 1 / max;
      for (var i = 0; i < peaks.length; i++) {
        peaks[i] = (peaks[i] * scale).clamp(0.0, 1.0);
      }
    }
    final int durationMs =
        (sampleCount / sampleRate * 1000).round();
    return WaveformPeaks._(peaks, sampleRate, durationMs);
  }

  /// Merges down to [targetBuckets] by taking the max of each window —
  /// used when zooming out (re-decode is unnecessary).
  WaveformPeaks downsample(int targetBuckets) {
    if (targetBuckets >= length || targetBuckets <= 0) {
      return this;
    }
    final Float32List peaks = Float32List(targetBuckets);
    final double per = length / targetBuckets;
    for (var t = 0; t < targetBuckets; t++) {
      final int start = (t * per).floor();
      final int end = ((t + 1) * per).ceil().clamp(0, length);
      double m = 0;
      for (var i = start; i < end; i++) {
        if (_peaks[i] > m) {
          m = _peaks[i];
        }
      }
      peaks[t] = m;
    }
    return WaveformPeaks._(peaks, sampleRate, durationMs);
  }
}

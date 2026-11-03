/// Capability interface for engines that can apply a software equalizer
/// (Stage 4, DAP-class feature 2.2).
///
/// This is deliberately a SEPARATE interface — `PlaybackEngine` stays
/// untouched so every engine, test fake and scripted engine keeps
/// compiling. Engines that support EQ also implement [EqualizerControl]
/// and callers opt in with an `is EqualizerControl` check:
///
/// ```dart
/// final eq = engine is EqualizerControl ? engine : null;
/// ```
///
/// Implementations:
/// - `MobilePlaybackEngine` (Android only) — just_audio `AudioPipeline`
///   with an `AndroidEqualizer` (device-reported band count / range).
/// - `DesktopPlaybackEngine` (media_kit) — a synthetic 10-band EQ pushed to
///   libmpv as a `lavfi=[equalizer=...]` audio-filter chain (see
///   `eq_filter.dart`).
///
/// All engine-side methods are best-effort and non-throwing: they return
/// `false` / `null` when the platform refuses or the underlying plugin
/// errors, so a broken EQ can never break playback.
library;

/// Static facts about an engine's equalizer implementation.
class EqualizerInfo {
  /// Creates the descriptor.
  const EqualizerInfo({
    required this.bandCount,
    required this.bandFrequencies,
    required this.minGainDb,
    required this.maxGainDb,
  });

  /// Number of bands the engine exposes.
  final int bandCount;

  /// Center frequencies (Hz) of the bands, ascending. May contain a
  /// placeholder value per band when the platform does not report the real
  /// center frequency.
  final List<double> bandFrequencies;

  /// Lowest per-band gain (dB, inclusive).
  final double minGainDb;

  /// Highest per-band gain (dB, inclusive).
  final double maxGainDb;
}

/// Opt-in equalizer capability (see the library doc).
abstract class EqualizerControl {
  /// Whether the engine can actually apply EQ on this platform. Cheap
  /// synchronous check for UI gating; the async handshake is
  /// [queryEqualizer].
  bool get equalizerAvailable;

  /// Platform-reported EQ facts, or `null` when the equalizer is
  /// unavailable (engine not connected, unsupported platform, plugin
  /// error).
  Future<EqualizerInfo?> queryEqualizer();

  /// Enables or disables the whole equalizer. Returns `true` on success.
  Future<bool> setEqualizerEnabled(bool enabled);

  /// Sets the gain (dB) of the band at [bandIndex]. Out-of-range indices
  /// return `false` without throwing.
  Future<bool> setEqualizerBandGain(int bandIndex, double gainDb);
}

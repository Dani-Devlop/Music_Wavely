/// Pure builders for the libmpv audio-filter string used by the desktop
/// (media_kit) equalizer implementation.
///
/// mpv exposes the FFmpeg filter graph via the `af` property. A parametric
/// band is expressed as `equalizer=f=<Hz>:t=q:w=<Q>:g=<dB>` and several
/// bands are chained with commas inside one `lavfi=[...]` wrapper:
///
/// ```text
/// af=lavfi=[equalizer=f=31:t=q:w=1.41:g=4.00,equalizer=f=62:t=q:w=1.41:g=-2.00]
/// ```
///
/// The whole string is a pure function of (frequencies, gains) so it is
/// unit-tested without a running player (`test/playback/equalizer/
/// eq_filter_test.dart`); `DesktopPlaybackEngine` only ships the resulting
/// string to `NativePlayer.setProperty('af', ...)`.
library;

/// Default Q factor used for every band (wide-ish peaking filter — the
/// value mpv's own examples use for music mastering).
const double kDefaultEqQuality = 1.41;

/// Builds the mpv `af` value for the given band [gainsDb] (dB) at the
/// matching [frequencies] (Hz, ascending).
///
/// - Bands with a gain of exactly `0` are omitted (flat bands are
///   no-ops — keeps the filter short).
/// - When every gain is flat the result is the empty string, which callers
///   push to mpv to RESET the filter chain (mpv `af=` clears it).
/// - Extra gains beyond [frequencies] (or vice versa) are ignored, so a
///   mismatch can never crash the engine.
String buildLavfiEqualizer(
  List<double> frequencies,
  List<double> gainsDb, {
  double quality = kDefaultEqQuality,
}) {
  final List<String> filters = <String>[];
  final int count =
      frequencies.length < gainsDb.length ? frequencies.length : gainsDb.length;
  for (var i = 0; i < count; i++) {
    final double gain = gainsDb[i];
    if (gain == 0) {
      continue;
    }
    filters.add(
      'equalizer=f=${frequencies[i].toStringAsFixed(0)}'
      ':t=q:w=${quality.toStringAsFixed(2)}'
      ':g=${gain.toStringAsFixed(2)}',
    );
  }
  if (filters.isEmpty) {
    return '';
  }
  return 'lavfi=[${filters.join(',')}]';
}

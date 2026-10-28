/// Censor-fallback policy (Stage 3 final polish, BUG-9).
///
/// Decides what happens when parental controls judge a track explicit but
/// censoring is IMPOSSIBLE — unsynced lyrics (no mute plan) or a failed
/// ffmpeg render. The legacy v1 rule was "censoring must never block
/// playback", i.e. the uncensored original played with only an audit trail
/// (SEC-6). That default is gone: the policy is an explicit parental choice
/// and DEFAULTS TO [block] — never silently to uncensored playback.
enum NoLyricsPolicy {
  /// Skip the track (with a UI toast). The safe default.
  block,

  /// Play the original with the engine volume muted (nothing audible).
  mute,

  /// Legacy v1 behavior: play the uncensored original (audited).
  allow;

  /// Parses the settings-store string; any unknown/absent value falls back
  /// to [block] (fail-safe, per the BUG-9 decision "do not default to
  /// uncensored playback").
  static NoLyricsPolicy parse(String? raw) {
    for (final value in NoLyricsPolicy.values) {
      if (value.name == raw) {
        return value;
      }
    }
    return NoLyricsPolicy.block;
  }
}

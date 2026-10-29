/// Formatting helpers on [Duration] used across playback UIs.
extension DurationX on Duration {
  /// Duration in one of the two canonical player shapes:
  ///
  /// - `H:MM:SS` when the duration is at least one hour (unpadded hours).
  /// - `MM:SS` otherwise (minutes and seconds are zero padded to two digits).
  ///
  /// Examples: 0s -> `00:00`, 59s -> `00:59`, 61s -> `01:01`,
  /// 3600s -> `1:00:00`, 3661s -> `1:01:01`.
  String get hm {
    final totalSeconds = inSeconds.abs();
    final hours = totalSeconds ~/ Duration.secondsPerHour;
    final minutes =
        (totalSeconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
    final seconds = totalSeconds % Duration.secondsPerMinute;
    final mm = _pad2(minutes);
    final ss = _pad2(seconds);
    if (hours > 0) {
      return '$hours:$mm:$ss';
    }
    return '$mm:$ss';
  }

  /// [hm] for positive durations, an en dash for zero / negative ones.
  String get hmOrDash => this <= Duration.zero ? '–' : hm;

  /// Always zero padded `HH:MM:SS`, e.g. 3661s -> `01:01:01`.
  String get digitalClock {
    final totalSeconds = inSeconds.abs();
    final hours = totalSeconds ~/ Duration.secondsPerHour;
    final minutes =
        (totalSeconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
    final seconds = totalSeconds % Duration.secondsPerMinute;
    return '${_pad2(hours)}:${_pad2(minutes)}:${_pad2(seconds)}';
  }

  String _pad2(int value) => value.toString().padLeft(2, '0');
}

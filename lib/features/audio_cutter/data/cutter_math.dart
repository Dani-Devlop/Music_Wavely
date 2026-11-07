/// Timestamp / selection math for the audio cutter (Phase 7.2).
///
/// Pure functions only — every rule the UI needs (parsing `mm:ss(.mmm)`,
/// formatting, clamping a selection into a valid range, minimum length,
/// ringtone length limits) is unit-testable here without Flutter.
library;

/// Minimum selectable/processable length.
const Duration kMinCutLength = Duration(milliseconds: 100);

/// Android ringtone/notification/alarm length guidance (RingtoneManager
/// plays the whole file; Musicolet warns past ~30 s for notifications).
const Duration kRingtoneSoftLimit = Duration(seconds: 30);

/// Parses `ss`, `mm:ss`, `hh:mm:ss` and optional fractional parts
/// (`.mmm` or `,mmm`) into a [Duration]. Returns `null` on garbage.
Duration? parseCutTimestamp(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  // Normalize comma decimals to dot.
  final String normalized = trimmed.replaceAll(',', '.');
  final List<String> parts = normalized.split(':');
  if (parts.isEmpty || parts.length > 3) {
    return null;
  }
  // Seconds part may carry the fraction.
  final RegExp secPattern = RegExp(r'^(\d+)(?:\.(\d{1,3}))?$');
  final RegExpMatch? secMatch = secPattern.firstMatch(parts.last);
  if (secMatch == null) {
    return null;
  }
  final int seconds = int.parse(secMatch.group(1)!);
  final String fraction = secMatch.group(2) ?? '';
  final int milliseconds = fraction.isEmpty
      ? 0
      : int.parse(fraction.padRight(3, '0').substring(0, 3));

  int minutes = 0;
  int hours = 0;
  if (parts.length >= 2) {
    final int? m = int.tryParse(parts[parts.length - 2]);
    if (m == null || m < 0) {
      return null;
    }
    minutes = m;
  }
  if (parts.length == 3) {
    final int? h = int.tryParse(parts[0]);
    if (h == null || h < 0) {
      return null;
    }
    hours = h;
  }
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: milliseconds,
  );
}

/// Formats [position] as `mm:ss` (or `hh:mm:ss` past an hour), truncating
/// sub-second precision.
String formatCutTimestamp(Duration position) {
  final int totalSeconds = position.inSeconds;
  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${two(minutes)}:${two(seconds)}';
  }
  return '${two(minutes)}:${two(seconds)}';
}

/// Formats with millisecond precision (`mm:ss.mmm`) — used for FFmpeg
/// `-ss`/`-t` values.
String formatCutTimestampMs(Duration position) {
  final String base = formatCutTimestamp(position);
  final int ms = position.inMilliseconds % 1000;
  return '$base.${ms.toString().padLeft(3, '0')}';
}

/// A validated cut selection within a track.
class CutSelection {
  const CutSelection({required this.start, required this.end});

  final Duration start;
  final Duration end;

  Duration get length => end - start;

  bool get isValid =>
      !start.isNegative &&
      end > start &&
      length >= kMinCutLength;
}

/// Clamps a raw selection into [CutSelection]:
/// - orders start/end,
/// - clamps both into `[Duration.zero, trackLength]`,
/// - enforces [kMinCutLength] (end grows to start+min when too short,
///   capped at trackLength; when even that is impossible the selection
///   collapses to the largest suffix the track allows).
CutSelection clampSelection(Duration a, Duration b, Duration trackLength) {
  final Duration clampedTrack =
      trackLength < Duration.zero ? Duration.zero : trackLength;
  Duration start = a <= b ? a : b;
  Duration end = a <= b ? b : a;
  if (start.isNegative) {
    start = Duration.zero;
  }
  if (start > clampedTrack) {
    start = clampedTrack;
  }
  if (end > clampedTrack) {
    end = clampedTrack;
  }
  if (end < start) {
    end = start;
  }
  if (end - start < kMinCutLength) {
    final Duration grown = start + kMinCutLength;
    if (grown <= clampedTrack) {
      end = grown;
    } else {
      // Back off from the track end.
      final Duration backed = clampedTrack - kMinCutLength;
      if (!backed.isNegative) {
        start = backed;
        end = clampedTrack;
      } else {
        start = Duration.zero;
        end = clampedTrack;
      }
    }
  }
  return CutSelection(start: start, end: end);
}

/// Ringtone kind for the "set as …" flow.
enum RingtoneKind { ringtone, notification, alarm }

/// Human label for [RingtoneKind].
extension RingtoneKindLabel on RingtoneKind {
  String get label => switch (this) {
        RingtoneKind.ringtone => 'Ringtone',
        RingtoneKind.notification => 'Notification',
        RingtoneKind.alarm => 'Alarm',
      };
}

/// Validation for the save-as-ringtone flow: returns a warning string or
/// `null` when the selection is fine.
String? ringtoneLengthWarning(CutSelection selection, RingtoneKind kind) {
  final Duration length = selection.length;
  if (kind == RingtoneKind.notification && length > kRingtoneSoftLimit) {
    return 'Notifications longer than '
        '${formatCutTimestamp(kRingtoneSoftLimit)} may be truncated '
        'by the system';
  }
  return null;
}

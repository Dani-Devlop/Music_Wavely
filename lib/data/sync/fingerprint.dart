import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:wavely/domain/entities/entities.dart';

/// Stable cross-device identity of a played track.
///
/// Format (Stage 1.2 spec): sha1 over
/// `$sourceId:$sourceTrackId:$title:$artist`, every component trimmed and
/// lower-cased first, joined with `:`. The fingerprint is what the sync
/// engine stores in outbox payloads and what remote plays are matched by —
/// it must therefore stay byte-stable across app versions.
String playFingerprint(Track track) => playFingerprintOf(
      sourceId: track.sourceId,
      sourceTrackId: track.sourceTrackId,
      title: track.title,
      artist: track.artist,
    );

/// Component-level variant of [playFingerprint] for rows that were never
/// mapped to a [Track] (e.g. SQL aggregates joining `plays` and `tracks`).
String playFingerprintOf({
  required String sourceId,
  required String sourceTrackId,
  required String title,
  required String artist,
}) {
  final key = <String>[
    sourceId.trim().toLowerCase(),
    sourceTrackId.trim().toLowerCase(),
    title.trim().toLowerCase(),
    artist.trim().toLowerCase(),
  ].join(':');
  return sha1.convert(utf8.encode(key)).toString();
}

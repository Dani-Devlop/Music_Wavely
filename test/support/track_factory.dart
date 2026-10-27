/// Authored, awaiting local run (Task 2-a).
///
/// Deterministic [Track] factory helpers for the Wavely test tree.
///
/// Every track produced here is stable across runs:
/// - `id` ascends from a configurable first id,
/// - `title` / `artist` / `album` / `genre` follow fixed cyclic formulas,
/// - `durationMs` grows linearly with the index,
/// - `addedAt` / `updatedAt` anchor to a fixed UTC base timestamp.
///
/// Tests needing custom fields pass overrides on top of the seed formula.
/// [Track] is a freezed value type, so two identical seeds compare equal.

import 'package:wavely/domain/entities/entities.dart';

/// Fixed base timestamp all generated [Track]s anchor to (12:00 UTC on
/// 2024-01-01) — deliberately not midnight so DST/date-boundary bugs in
/// formatting or grouping code are observable.
final DateTime kTrackFactoryBaseTime = DateTime.utc(2024, 1, 1, 12);

/// Builds one deterministic [Track] for [index] (1-based by convention).
///
/// Overrides replace the computed defaults; everything else stays stable.
/// The seed formulas are:
/// - `id`                → [id] ?? [index]
/// - `sourceId`          → [sourceId] ?? `Track.localSourceId`
/// - `sourceTrackId`     → [sourceTrackId] ?? `'seed-<id>'`
/// - `title`             → `'Track <index>'`
/// - `artist`            → `'Artist 1..3'` cycling with the index
/// - `album`             → `'Album 1+'` advancing every three indices
/// - `genre`             → `'Genre 1..2'` cycling with the index
/// - `durationMs`        → `60000 + index * 30000` (1m, 1.5m, 2m, ...)
/// - `format`            → `'mp3'`
/// - `filePath`          → `'/music/seed/<id>.mp3'`
/// - `explicit`          → every 4th index
/// - `addedAt`/`updatedAt` → base time + [index] minutes
Track seedTrack(
  int index, {
  int? id,
  String? sourceId,
  String? sourceTrackId,
  String? title,
  String? artist,
  String? album,
  String? genre,
  String? language,
  int? durationMs,
  int? bitrate,
  String? format,
  String? filePath,
  String? coverPath,
  bool? explicit,
  DateTime? addedAt,
  DateTime? updatedAt,
  int? playCount,
  DateTime? lastPlayedAt,
}) {
  final resolvedId = id ?? index;
  final stamped = kTrackFactoryBaseTime.add(Duration(minutes: index));
  return Track(
    id: resolvedId,
    sourceId: sourceId ?? Track.localSourceId,
    sourceTrackId: sourceTrackId ?? 'seed-$resolvedId',
    title: title ?? 'Track $index',
    artist: artist ?? 'Artist ${((index - 1) % 3) + 1}',
    album: album ?? 'Album ${((index - 1) ~/ 3) + 1}',
    genre: genre ?? 'Genre ${((index - 1) % 2) + 1}',
    language: language,
    durationMs: durationMs ?? 60000 + index * 30000,
    bitrate: bitrate,
    format: format ?? 'mp3',
    filePath: filePath ?? '/music/seed/$resolvedId.mp3',
    coverPath: coverPath,
    explicit: explicit ?? index % 4 == 0,
    addedAt: addedAt ?? stamped,
    updatedAt: updatedAt ?? stamped,
    playCount: playCount ?? 0,
    lastPlayedAt: lastPlayedAt,
  );
}

/// Builds [count] deterministic tracks with consecutive ids starting at
/// [firstId].
///
/// [artist] / [album] / [genre], when given, pin those fields across the
/// whole batch (useful for grouping, artist-detail and album-detail tests);
/// otherwise each track keeps its own seeded value.
List<Track> seedTracks(
  int count, {
  int firstId = 1,
  String? artist,
  String? album,
  String? genre,
}) => <Track>[
      for (var i = 0; i < count; i++)
        seedTrack(
          firstId + i,
          artist: artist,
          album: album,
          genre: genre,
        ),
    ];

/// A single fully-overridden [Track] (no seeded formulas at all).
///
/// Convenience for tests that need one explicit, self-documenting fixture.
Track manualTrack({
  int? id,
  required String title,
  required String artist,
  required int durationMs,
  String sourceId = Track.localSourceId,
  String sourceTrackId = 'manual',
  String format = 'mp3',
}) =>
    Track(
      id: id,
      sourceId: sourceId,
      sourceTrackId: sourceTrackId,
      title: title,
      artist: artist,
      durationMs: durationMs,
      format: format,
      addedAt: kTrackFactoryBaseTime,
      updatedAt: kTrackFactoryBaseTime,
    );

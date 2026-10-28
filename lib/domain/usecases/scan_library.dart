import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/legacy.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/extensions/string_x.dart';
import 'package:wavely/core/utils/stable_hash.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/lyrics_dao.dart';
import 'package:wavely/data/local/db/daos/tracks_dao.dart';
import 'package:wavely/data/local/db/mappers/track_mapper.dart';
import 'package:wavely/domain/entities/entities.dart';

/// Number of files parsed per [Isolate.run] batch. A private constant because
/// it is scanner-tuning, not app-wide policy (kept out of [AppConstants]).
const int _batchSize = 32;

/// File extensions the scanner enumerates, without leading dot. Files with
/// other extensions are skipped silently (they never enter the event stream
/// and are not counted as errors).
const Set<String> _supportedExtensions = <String>{
  'mp3',
  'flac',
  'm4a',
  'aac',
  'ogg',
  'opus',
  'wav',
};

/// Bits per kilobit when normalising raw `bitrate` (bits per second) to kbps.
const int _bitsPerKilobit = 1000;

/// Regular expression matching LRC timestamps like `[00:01.00]` / `[1:2]`.
final RegExp _lrcTimestampPattern = RegExp(r'\[\d{1,3}:\d{2}(?:\.\d{1,3})?\]');

/// Fallback title when a file carries no usable tag: its filename stem.
String _titleFor(ScanFileResult result) =>
    (result.title?.isNotBlank ?? false)
        ? result.title!.trim()
        : p.basenameWithoutExtension(result.path).sanitized;

/// Fallback artist when a file carries no usable tag.
String _artistFor(ScanFileResult result) =>
    (result.artist?.isNotBlank ?? false)
        ? result.artist!.trim()
        : 'Unknown Artist';

/// True when [raw] looks like synced LRC (contains `[mm:ss(.fff)]` tags);
/// such text is stored as `syncedLrc`, everything else as `plainText`.
bool _looksLikeLrc(String raw) => _lrcTimestampPattern.hasMatch(raw);

/// The result of parsing one audio file inside a scanner isolate.
///
/// On success the metadata fields are populated; on failure [error] carries
/// the reason and everything else stays empty. Instances cross isolate
/// boundaries, so all fields must be primitive/sendable (cover art travels
/// as raw bytes and is written to disk on the main isolate).
class ScanFileResult {
  /// Successful parse of the file at [path].
  const ScanFileResult({
    required this.path,
    required this.fileSize,
    required this.mtime,
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.language,
    this.durationMs,
    this.bitrate,
    this.bitrateKbps,
    required this.format,
    this.lyricsRaw,
    this.coverBytes,
    this.coverMime,
  })  : error = null;

  /// Failed parse of the file at [path]; [error] explains why.
  const ScanFileResult.failed({
    required this.path,
    required this.fileSize,
    required this.mtime,
    required this.error,
  })  : title = null,
        artist = null,
        album = null,
        genre = null,
        language = null,
        durationMs = null,
        bitrate = null,
        bitrateKbps = null,
        format = '',
        lyricsRaw = null,
        coverBytes = null,
        coverMime = null;

  /// Absolute file path.
  final String path;

  /// Size in bytes at scan time.
  final int fileSize;

  /// Modification time at scan time (feeds the stable source id).
  final DateTime mtime;

  /// Tagged title, if any.
  final String? title;

  /// Tagged artist, if any.
  final String? artist;

  /// Tagged album, if any.
  final String? album;

  /// First tagged genre, if any.
  final String? genre;

  /// Tagged language, if any.
  final String? language;

  /// Duration in milliseconds, null when unknown.
  final int? durationMs;

  /// Raw bitrate in bits per second, null when unknown.
  final int? bitrate;

  /// Bitrate rounded down to kbps, null when unknown.
  final int? bitrateKbps;

  /// Lower-cased file extension without dot (e.g. `mp3`); empty on failure.
  final String format;

  /// Raw lyrics text found in the tags (plain or LRC), if any.
  final String? lyricsRaw;

  /// Embedded cover art bytes, if any (written to disk on the main isolate).
  final Uint8List? coverBytes;

  /// MIME type of [coverBytes] (e.g. `image/jpeg`).
  final String? coverMime;

  /// Failure reason; non-null marks this result as a parse failure.
  final String? error;

  /// True when the file failed to parse.
  bool get isFailure => error != null;
}

/// Scans folders for audio files, extracts metadata in batches on background
/// isolates, persists tracks (and embedded lyrics + cover art) and keeps the
/// album/artist projections in sync.
///
/// The [scan] stream is broadcast and never throws: every failure surfaces
/// as a [ScanError] event and the stream always ends with [ScanCompleted].
/// Track identity is `stableHash('$path:$size:$mtimeMs')`; duplicates within
/// one run are dropped, cross-run duplicates collapse via the DAO upsert.
///
/// Note (Stage 1.1 pragmatism): this usecase touches the drift DAOs
/// directly, as mandated by the scan pipeline design.
class ScanLibrary {
  /// Creates a scanner bound to the track/lyrics DAOs it persists through.
  ScanLibrary({
    required TracksDao tracksDao,
    required LyricsDao lyricsDao,
  })  : _tracksDao = tracksDao,
        _lyricsDao = lyricsDao;

  final TracksDao _tracksDao;
  final LyricsDao _lyricsDao;

  /// Scans [folders] (recursively) and emits [ScanEvent]s.
  ///
  /// When [coversDir] is non-null, embedded cover art is written to that
  /// directory as `<stableHash>.jpg|.png` and the track's [Track.coverPath]
  /// points at the file; when null (or the directory cannot be created)
  /// covers are skipped entirely.
  Stream<ScanEvent> scan({
    required List<String> folders,
    String? coversDir,
  }) {
    // Single-subscription + lazy start: _run begins on the FIRST listen so
    // the leading ScanStarted is never emitted before a subscriber exists
    // (a broadcast controller would silently drop it — the stream contract
    // is "ScanStarted first, ScanCompleted last").
    late final StreamController<ScanEvent> controller;
    controller = StreamController<ScanEvent>(
      onListen: () => unawaited(_run(controller, folders, coversDir)),
    );
    return controller.stream;
  }

  Future<void> _run(
    StreamController<ScanEvent> controller,
    List<String> folders,
    String? coversDir,
  ) async {
    final errors = <String>[];
    var persisted = 0;
    try {
      final files = _enumerate(folders, controller, errors);
      controller.add(
        ScanEvent.scanStarted(root: folders.isEmpty ? '' : folders.first),
      );
      var effectiveCoversDir = coversDir;
      if (effectiveCoversDir != null) {
        try {
          Directory(effectiveCoversDir).createSync(recursive: true);
        } on Object catch (_) {
          // Covers are best-effort; scanning continues without them.
          effectiveCoversDir = null;
        }
      }
      final seen = <String>{};
      final albumKeys = <({String artist, String album})>{};
      final artistNames = <String>{};
      var processed = 0;
      for (var start = 0; start < files.length; start += _batchSize) {
        // Stage 3 audit (BUG-7): honour cancellation between batches. The
        // listener IS the cancel token (ScanStateNotifier.cancel cancels
        // the subscription); only treated as cancelled once at least one
        // batch ran, so a stream that nobody has subscribed to yet is not
        // misread as a cancelled scan. Previously "cancel" merely detached
        // the UI while the scan kept parsing and writing to completion.
        if (processed > 0 && !controller.hasListener) {
          break;
        }
        final next = start + _batchSize;
        final end = next < files.length ? next : files.length;
        final batch = files.sublist(start, end);
        final results = await Isolate.run(
          () => _scanBatch(batch, getImage: effectiveCoversDir != null),
        );
        for (final result in results) {
          processed++;
          if (result.isFailure) {
            final reason = result.error ?? 'unknown metadata error';
            if (errors.length < AppConstants.scanErrorLogLimit) {
              errors.add('${result.path}: $reason');
            }
            controller.add(ScanEvent.error(file: result.path, reason: reason));
          } else {
            final track = await _persist(
              result,
              effectiveCoversDir,
              seen,
              albumKeys,
              artistNames,
            );
            if (track != null) {
              persisted++;
              controller.add(ScanEvent.trackFound(track: track));
            }
          }
          controller.add(
            ScanEvent.progress(
              processed: processed,
              total: files.length,
              currentFile: result.path,
            ),
          );
        }
      }
      for (final key in albumKeys) {
        await _tracksDao.upsertAlbumProjection(
          title: key.album,
          artist: key.artist,
        );
      }
      for (final artist in artistNames) {
        await _tracksDao.upsertArtistProjection(name: artist);
      }
      controller.add(
        ScanEvent.completed(count: persisted, errors: List.of(errors)),
      );
    } on Object catch (e) {
      controller.add(
        ScanEvent.error(
          file: folders.firstOrNull ?? '',
          reason: e.toString(),
        ),
      );
      controller.add(
        ScanEvent.completed(count: persisted, errors: List.of(errors)),
      );
    } finally {
      await controller.close();
    }
  }

  /// Collects supported audio files below [folders]; unreadable folders
  /// surface as [ScanError] events but never abort the scan.
  List<String> _enumerate(
    List<String> folders,
    StreamController<ScanEvent> controller,
    List<String> errors,
  ) {
    final files = <String>[];
    for (final folder in folders) {
      try {
        final dir = Directory(folder);
        if (!dir.existsSync()) {
          continue;
        }
        for (final entity
            in dir.listSync(recursive: true, followLinks: false)) {
          if (entity is! File) {
            continue;
          }
          final extension =
              p.extension(entity.path).replaceFirst('.', '').toLowerCase();
          if (_supportedExtensions.contains(extension)) {
            files.add(entity.path);
          }
        }
      } on Object catch (e) {
        if (errors.length < AppConstants.scanErrorLogLimit) {
          errors.add('$folder: $e');
        }
        controller.add(ScanEvent.error(file: folder, reason: e.toString()));
      }
    }
    return files;
  }

  /// Persists one successfully parsed file: writes the cover (if any),
  /// upserts the track, stores embedded lyrics and records the artist/album
  /// keys for the projection post-pass. Returns null for within-run
  /// duplicates.
  Future<Track?> _persist(
    ScanFileResult result,
    String? coversDir,
    Set<String> seen,
    Set<({String artist, String album})> albumKeys,
    Set<String> artistNames,
  ) async {
    final mtimeMs = result.mtime.millisecondsSinceEpoch;
    final sourceTrackId =
        stableHash('${result.path}:${result.fileSize}:$mtimeMs');
    if (!seen.add(sourceTrackId)) {
      return null;
    }
    String? coverPath;
    if (coversDir != null) {
      coverPath = await _writeCover(coversDir, result);
    }
    final now = DateTime.now();
    final track = Track(
      sourceId: Track.localSourceId,
      sourceTrackId: sourceTrackId,
      title: _titleFor(result),
      artist: _artistFor(result),
      album: result.album,
      genre: result.genre,
      language: result.language,
      durationMs: result.durationMs ?? 0,
      bitrate: result.bitrateKbps,
      format: result.format,
      filePath: result.path,
      coverPath: coverPath,
      addedAt: now,
      updatedAt: now,
    );
    final persistedTrack =
        await _tracksDao.upsertBySource(TrackMapper.toCompanion(track));
    final id = persistedTrack.id;
    final lyrics = result.lyricsRaw;
    if (id != null && lyrics != null && lyrics.isNotBlank) {
      final synced = _looksLikeLrc(lyrics);
      await _lyricsDao.upsert(
        trackId: id,
        provider: LyricsDao.embeddedProvider,
        syncedLrc: synced ? lyrics : null,
        plainText: synced ? null : lyrics,
      );
    }
    artistNames.add(persistedTrack.artist);
    final album = persistedTrack.album;
    if (album != null) {
      albumKeys.add((artist: persistedTrack.artist, album: album));
    }
    return persistedTrack;
  }

  /// Writes embedded cover art to `<coversDir>/<stableHash>.<ext>` and
  /// returns the path, or null when there is nothing to write / writing
  /// failed (covers are best-effort).
  Future<String?> _writeCover(String coversDir, ScanFileResult result) async {
    final bytes = result.coverBytes;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    const jpegExtension = '.jpg';
    const pngExtension = '.png';
    final extension =
        (result.coverMime ?? '').contains('png') ? pngExtension : jpegExtension;
    final name =
        '${stableHash('cover:${result.path}:${bytes.length}')}$extension';
    final file = File(p.join(coversDir, name));
    try {
      await file.writeAsBytes(bytes, flush: true);
    } on Object catch (_) {
      return null;
    }
    return file.path;
  }
}

/// Parses a batch of files on a background isolate.
///
/// Must stay a top-level function so [Isolate.run] can ship it across
/// isolate boundaries; only sendable values enter and leave.
List<ScanFileResult> _scanBatch(
  List<String> paths, {
  required bool getImage,
}) {
  final results = <ScanFileResult>[];
  for (final path in paths) {
    results.add(_scanOne(path, getImage: getImage));
  }
  return results;
}

/// Reads the tags of one file (never throws — failures become
/// [ScanFileResult.failed]).
ScanFileResult _scanOne(String path, {required bool getImage}) {
  final file = File(path);
  FileStat stat;
  try {
    stat = file.statSync();
  } on Object catch (e) {
    return ScanFileResult.failed(
      path: path,
      fileSize: 0,
      mtime: DateTime.fromMillisecondsSinceEpoch(0),
      error: e.toString(),
    );
  }
  AudioMetadata metadata;
  try {
    metadata = readMetadata(file, getImage: getImage);
  } on NoMetadataParserException catch (e) {
    return ScanFileResult.failed(
      path: path,
      fileSize: stat.size,
      mtime: stat.modified,
      error: 'no parser for ${e.track.path}',
    );
  } on MetadataParserException catch (e) {
    return ScanFileResult.failed(
      path: path,
      fileSize: stat.size,
      mtime: stat.modified,
      error: e.message,
    );
  } on Object catch (e) {
    return ScanFileResult.failed(
      path: path,
      fileSize: stat.size,
      mtime: stat.modified,
      error: e.toString(),
    );
  }
  final format = p.extension(path).replaceFirst('.', '').toLowerCase();
  final bitrate = metadata.bitrate;
  final cover = getImage ? metadata.pictures.firstOrNull : null;
  return ScanFileResult(
    path: path,
    fileSize: stat.size,
    mtime: stat.modified,
    title: metadata.title,
    artist: metadata.artist,
    album: metadata.album,
    genre: metadata.genres.firstOrNull,
    language: metadata.language,
    durationMs: metadata.duration?.inMilliseconds,
    bitrate: bitrate,
    bitrateKbps: bitrate == null ? null : bitrate ~/ _bitsPerKilobit,
    format: format,
    lyricsRaw: metadata.lyrics,
    coverBytes: cover?.bytes,
    coverMime: cover?.mimetype,
  );
}

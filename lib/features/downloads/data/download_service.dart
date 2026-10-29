import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/tables/downloads.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/features/downloads/data/download_events.dart';
import 'package:wavely/features/downloads/data/download_notifier.dart';
import 'package:wavely/features/downloads/data/download_prefs.dart';
import 'package:wavely/features/downloads/domain/filename_sanitizer.dart';
import 'package:wavely/features/downloads/domain/folder_template.dart';
import 'package:wavely/sources/download_file_exports.dart';

/// One in-flight job handle.
class _ActiveJob {
  _ActiveJob(this.cancelToken);

  final CancelToken cancelToken;
}

/// The download manager (Stage 2.1 Section 9).
///
/// - Queue with a configurable concurrency cap (default 3);
/// - per download: streaming GET with HTTP Range resume, progress → DB +
///   [events], size verification against Content-Length, sha-256 checksum
///   and a `<trackId>.wavely.json` provenance sidecar;
/// - retry 3× with exponential backoff (1 s, 2 s, 4 s), then `failed`;
/// - pause (cancel + keep partial, row → queued), cancel (delete partial),
///   retry (failed → queued);
/// - Wi-Fi-only gate: when enabled and the connectivity probe says the
///   connection is metered, queued jobs simply do not start.
///
/// The connectivity probe is injected by the composition root
/// (connectivity_plus is a UI/device concern); the service itself stays
/// testable without platform channels.
class DownloadService {
  /// Creates the service.
  ///
  /// [resolveSources] supplies the enabled sources (re-resolved per pump so
  /// settings changes apply). [baseDir] resolves the storage root
  /// (path_provider in production, tmp dir in tests). [isUnmetered] gates
  /// the Wi-Fi-only preference (`null` = treat every network as usable).
  /// [backoff] is injectable for retry tests.
  DownloadService({
    required AppDatabase db,
    required DownloadPrefs prefs,
    required Future<List<SourceProvider>> Function() resolveSources,
    required Future<String> Function() baseDir,
    DownloadFileExecutor? executor,
    DownloadNotifier notifier = const NoopDownloadNotifier(),
    FolderTemplate? folderTemplate,
    Dio? dio,
    Future<bool> Function()? isUnmetered,
    Future<void> Function(int attempt)? backoff,
  })  : _db = db,
        _prefs = prefs,
        _resolveSources = resolveSources,
        _baseDir = baseDir,
        _executor = executor ?? IoDownloadFileExecutor(),
        _notifier = notifier,
        _folderTemplate = folderTemplate ?? FolderTemplate(),
        _dio = dio ?? Dio(),
        _isUnmetered = isUnmetered,
        _backoff = backoff ?? _defaultBackoff;

  final AppDatabase _db;
  final DownloadPrefs _prefs;
  final Future<List<SourceProvider>> Function() _resolveSources;
  final Future<String> Function() _baseDir;
  final DownloadFileExecutor _executor;
  final DownloadNotifier _notifier;
  final FolderTemplate _folderTemplate;
  final Dio _dio;
  final Future<bool> Function()? _isUnmetered;
  final Future<void> Function(int attempt) _backoff;

  final Map<int, _ActiveJob> _active = <int, _ActiveJob>{};
  var _pumping = false;

  final StreamController<DownloadEvent> _events =
      StreamController<DownloadEvent>.broadcast();

  /// Broadcast stream of every lifecycle event.
  Stream<DownloadEvent> get events => _events.stream;

  static Future<void> _defaultBackoff(int attempt) =>
      Future<void>.delayed(Duration(seconds: 1 << (attempt - 1)));

  /// Boot-time repair: `downloading` rows from a crash go back to queued
  /// (their partial files resume via HTTP Range on the next pump).
  Future<void> start() async {
    await _db.downloadsDao.resetInterrupted();
    await pump();
  }

  /// Enqueues [track] for download and kicks the pump. Returns the row id.
  Future<int> enqueue(
    Track track, {
    String? quality,
    String? licenseUrl,
  }) async {
    // Stage 3 audit (BUG-5): dedupe — two enqueues of the same track used to
    // create two jobs writing the same target file concurrently (corruption).
    final DownloadRow? existing = await _db.downloadsDao.activeForSourceTrack(
      track.sourceId,
      track.sourceTrackId,
    );
    if (existing != null) {
      _emit(DownloadEvent(rowId: existing.id, status: existing.status));
      await pump();
      return existing.id;
    }
    final String dir = await _folderTemplate.renderFor(
      track,
      baseDir: await _resolveBaseDir(),
    );
    // The quality segment is appended by the service (not the template) so
    // user templates stay stable across quality changes: default layout is
    // `<base>/Music/<geo>/<genre>/<quality>/<file>`.
    final String targetPath =
        '$dir/${sanitizeFilename(quality ?? _prefs.quality)}/${buildTrackFilename(track.title, track.format)}';
    final int rowId = await _db.downloadsDao.enqueue(
      DownloadsCompanion.insert(
        sourceId: track.sourceId,
        sourceTrackId: track.sourceTrackId,
        targetPath: targetPath,
        quality: quality ?? _prefs.quality,
        status: DownloadStatus.queued,
        progress: 0,
        startedAt: DateTime.now(),
      ),
    );
    _emit(DownloadEvent(rowId: rowId, status: DownloadStatus.queued));
    await pump();
    return rowId;
  }

  Future<String> _resolveBaseDir() async {
    final String configured = _prefs.baseDir;
    if (configured.isNotEmpty) {
      return configured;
    }
    return _baseDir();
  }

  /// Starts as many queued jobs as the concurrency cap allows.
  Future<void> pump() async {
    if (_pumping) {
      return;
    }
    _pumping = true;
    try {
      final bool unmetered =
          _prefs.wifiOnly ? await (_isUnmetered?.call() ?? Future<bool>.value(true)) : true;
      if (_prefs.wifiOnly && !unmetered) {
        return;
      }
      while (_active.length < _prefs.concurrency) {
        final List<DownloadRow> pending = await _db.downloadsDao.pending();
        final DownloadRow? next = pending
            .where((DownloadRow r) => !_active.containsKey(r.id))
            .firstOrNull;
        if (next == null) {
          break;
        }
        final CancelToken token = CancelToken();
        _active[next.id] = _ActiveJob(token);
        // Fire-and-forget: the job removes itself when done.
        unawaited(_runJob(next, token));
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _runJob(DownloadRow row, CancelToken token) async {
    try {
      await _db.downloadsDao.markStatus(row.id, DownloadStatus.downloading);
      _emit(DownloadEvent(rowId: row.id, status: DownloadStatus.downloading));
      await _notifier.notifyStarted(row.sourceTrackId);

      final SourceProvider? source = await _sourceFor(row.sourceId);
      if (source == null) {
        throw StateError('source ${row.sourceId} is not available');
      }
      final StreamUrl stream = await source.resolveStream(_minimalTrack(row));
      final String? license = await _licenseFor(source, row);

      await _downloadWithRetry(row, stream.url, token, license);

      await _notifier.notifyCompleted(row.sourceTrackId);
      _emit(DownloadEvent(rowId: row.id, status: DownloadStatus.completed));
    } on Object catch (e) {
      final bool canceled =
          e is DioException && e.type == DioExceptionType.cancel;
      if (canceled) {
        // pause() / cancel() already wrote the status they wanted.
        return;
      }
      await _db.downloadsDao.markStatus(
        row.id,
        DownloadStatus.failed,
        errorMessage: e.toString(),
      );
      await _notifier.notifyFailed(row.sourceTrackId, e.toString());
      _emit(
        DownloadEvent(
          rowId: row.id,
          status: DownloadStatus.failed,
          error: e.toString(),
        ),
      );
    } finally {
      // Stage 3 audit (BUG-4): only remove the job if it is still ours — a
      // pause() during unwind may have already started a replacement job for
      // this row, and removing that one orphaned it (unpausable + concurrent
      // writers on one file).
      if (identical(_active[row.id]?.cancelToken, token)) {
        _active.remove(row.id);
      }
      await pump();
    }
  }

  Future<void> _downloadWithRetry(
    DownloadRow row,
    String url,
    CancelToken token,
    String? license,
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await _downloadOnce(row, url, token, license);
        return;
      } on Object catch (e) {
        if (e is DioException && e.type == DioExceptionType.cancel) {
          rethrow;
        }
        // A size mismatch is a permanent protocol error (truncated body,
        // lying Content-Length): resuming cannot fix it, so fail fast
        // instead of burning the remaining attempts on the same bytes.
        if (e is _SizeMismatchError) {
          rethrow;
        }
        lastError = e;
        if (attempt < 3) {
          await _backoff(attempt);
        }
      }
    }
    throw lastError ?? StateError('download failed after 3 attempts');
  }

  Future<void> _downloadOnce(
    DownloadRow row,
    String url,
    CancelToken token,
    String? license,
  ) async {
    // The quality segment is appended by the service, so the leaf directory
    // may not exist even when the template part does — create it before the
    // first byte is written (idempotent, cheap on the io arm).
    await _executor.ensureDir(_dirOf(row.targetPath));
    var offset = await _executor.exists(row.targetPath)
        ? await _executor.fileSize(row.targetPath)
        : 0;
    final Map<String, String> headers = <String, String>{
      if (offset > 0) 'Range': 'bytes=$offset-',
    };
    final Response<ResponseBody> res = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: headers,
        // 200 (full body) or 206 (range honoured); anything else is an error.
        validateStatus: (int? code) =>
            code != null && (code == 200 || code == 206),
      ),
      cancelToken: token,
    );

    if (res.statusCode == 200 && offset > 0) {
      // Server ignored the Range header — restart from scratch so we never
      // append duplicate bytes.
      await _executor.delete(row.targetPath);
      offset = 0;
    }

    final int? totalLength = _totalLengthOf(res.headers, offset);

    // Stream to disk in ~1 MB batches; position = offset + bytes written.
    var received = 0;
    var lastPercent = -1;
    final List<int> batch = <int>[];
    Future<void> flush() async {
      if (batch.isEmpty) {
        return;
      }
      await _executor.writeFromStream(
        Stream<List<int>>.fromIterable(<List<int>>[batch]),
        row.targetPath,
        startOffset: offset + received - batch.length,
      );
      batch.clear();
    }

    await for (final List<int> chunk in res.data!.stream) {
      batch.addAll(chunk);
      received += chunk.length;
      if (batch.length >= 1024 * 1024) {
        await flush();
      }
      if (totalLength != null) {
        final int percent = ((offset + received) / totalLength * 100)
            .floor()
            .clamp(0, 100);
        if (percent != lastPercent) {
          lastPercent = percent;
          await _db.downloadsDao.updateProgress(row.id, percent);
          _emit(
            DownloadEvent(
              rowId: row.id,
              status: DownloadStatus.downloading,
              progress: percent,
            ),
          );
        }
      }
    }
    await flush();

    // Size verification against Content-Length / Content-Range total.
    final int finalSize = offset + received;
    if (totalLength != null && finalSize != totalLength) {
      throw _SizeMismatchError(
        'size mismatch: expected $totalLength bytes, got $finalSize',
      );
    }

    // Checksum over the finished file (crypto streams the read).
    final String checksum =
        'sha256:${(await sha256.bind(_executor.readStream(row.targetPath)).first)}';

    final String provenance = _provenanceJson(
      row: row,
      url: url,
      license: license,
      quality: row.quality,
      checksum: checksum,
    );
    // Stage 3 audit (SEC-3): sourceTrackId comes from remote APIs and must
    // never be able to traverse paths — sanitize before composing the name.
    final String sidecarPath =
        '${_dirOf(row.targetPath)}/${sanitizeFilename(row.sourceTrackId, maxLength: 120)}.wavely.json';
    await _executor.writeString(sidecarPath, provenance);
    await _db.downloadsDao.markStatus(
      row.id,
      DownloadStatus.completed,
      completedAt: DateTime.now(),
      provenanceJson: provenance,
    );
  }

  static int? _totalLengthOf(Headers headers, int offset) {
    final String? contentRange = headers.value('content-range');
    if (contentRange != null) {
      final Match? m =
          RegExp(r'bytes \d+-\d+/(\d+)').firstMatch(contentRange);
      if (m != null) {
        return int.tryParse(m.group(1)!);
      }
    }
    final String? len = headers.value('content-length');
    if (len != null) {
      final int? v = int.tryParse(len);
      if (v != null) {
        return offset > 0 ? offset + v : v;
      }
    }
    return null;
  }

  String _provenanceJson({
    required DownloadRow row,
    required String url,
    required String? license,
    required String quality,
    required String checksum,
  }) =>
      jsonEncode(<String, dynamic>{
        'source': row.sourceId,
        'sourceId': row.sourceTrackId,
        // Stage 3 audit (SEC-4): provenance must not embed replayable
        // credentials (Subsonic `t=`/`s=`/`p=` auth params, api keys).
        'url': _redactedProvenanceUrl(url),
        'license': license ?? 'unknown',
        'downloadedAt': DateTime.now().toUtc().toIso8601String(),
        'quality': quality,
        'checksum': checksum,
      });

  /// Strips credential-bearing query parameters from a persisted URL while
  /// keeping scheme/host/path for provenance display.
  String _redactedProvenanceUrl(String rawUrl) {
    final Uri? uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return rawUrl;
    }
    final Map<String, String> params =
        Map<String, String>.of(uri.queryParameters)
          ..remove('t')
          ..remove('s')
          ..remove('p')
          ..remove('token')
          ..remove('api_key')
          ..remove('apikey')
          ..remove('key');
    return uri
        .replace(queryParameters: params.isEmpty ? null : params)
        .toString();
  }

  String _dirOf(String path) {
    final int i = path.lastIndexOf('/');
    return i <= 0 ? '/' : path.substring(0, i);
  }

  Track _minimalTrack(DownloadRow row) {
    final DateTime now = DateTime.now().toUtc();
    return Track(
      sourceId: row.sourceId,
      sourceTrackId: row.sourceTrackId,
      title: '',
      artist: '',
      durationMs: 0,
      format: '',
      addedAt: now,
      updatedAt: now,
    );
  }

  Future<SourceProvider?> _sourceFor(String sourceId) async {
    final List<SourceProvider> sources = await _resolveSources();
    for (final SourceProvider s in sources) {
      if (s.id == sourceId) {
        return s;
      }
    }
    return null;
  }

  Future<String?> _licenseFor(
    SourceProvider source,
    DownloadRow row,
  ) async {
    try {
      final Map<String, dynamic> meta =
          await source.getMetadata(row.sourceTrackId);
      for (final String key in const <String>[
        'license_ccurl',
        'licenseurl',
        'licenseUrl',
        'license',
      ]) {
        final Object? v = meta[key];
        if (v is String && v.isNotEmpty) {
          return v;
        }
      }
      return null;
    } on Object {
      return null;
    }
  }

  /// Pauses [rowId]: cancels the in-flight HTTP stream, keeps the partial
  /// file, sets the row back to `queued` (resume = next pump with Range).
  Future<void> pause(int rowId) async {
    final _ActiveJob? job = _active[rowId];
    if (job != null) {
      job.cancelToken.cancel('paused');
      // Stage 3 audit (BUG-4): do NOT remove the job here — the cancelled
      // _runJob removes itself (identity-checked) when it unwinds. Removing
      // eagerly let pump() start a second concurrent writer on the file.
    }
    await _db.downloadsDao.markStatus(rowId, DownloadStatus.queued);
    _emit(DownloadEvent(rowId: rowId, status: DownloadStatus.queued));
    await pump();
  }

  /// Cancels [rowId] and deletes the partial file.
  Future<void> cancel(int rowId) async {
    final _ActiveJob? job = _active[rowId];
    if (job != null) {
      job.cancelToken.cancel('canceled');
      // Stage 3 audit (BUG-4): job removes itself when unwound (identity-
      // checked) — see pause().
    }
    final DownloadRow? row = await _db.downloadsDao.byId(rowId);
    if (row != null) {
      // Unconditional: the executor implementations tolerate a missing
      // file, and recording the delete keeps cancel semantics honest even
      // when no bytes landed yet.
      await _executor.delete(row.targetPath);
    }
    await _db.downloadsDao.markStatus(
      rowId,
      DownloadStatus.canceled,
      completedAt: DateTime.now(),
    );
    _emit(DownloadEvent(rowId: rowId, status: DownloadStatus.canceled));
    await pump();
  }

  /// Re-queues a failed (or canceled) job.
  Future<void> retry(int rowId) async {
    await _db.downloadsDao.markStatus(rowId, DownloadStatus.queued);
    _emit(DownloadEvent(rowId: rowId, status: DownloadStatus.queued));
    await pump();
  }

  void _emit(DownloadEvent e) {
    if (!_events.isClosed) {
      _events.add(e);
    }
  }

  /// Closes the event stream (composition-root teardown).
  Future<void> dispose() => _events.close();
}

/// Permanent size-verification failure (non-retryable): the delivered body
/// does not match the declared Content-Length / Content-Range total, so
/// resuming cannot fix it — the job fails immediately.
class _SizeMismatchError extends Error {
  _SizeMismatchError(this.message);

  final String message;

  @override
  String toString() => message;
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/themes/theme_provider.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/library_scanner.dart';
import 'package:wavely/features/library/data/library_scanner_provider.dart';

/// One page of the library track list, [AppConstants.scrollPageSize] items
/// each, ordered by title (case-folded).
final tracksPagedProvider =
    FutureProvider.family<List<Track>, int>((ref, page) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  return dao.getAll(
    limit: AppConstants.scrollPageSize,
    offset: page * AppConstants.scrollPageSize,
  );
});

/// All library tracks of one artist, grouped by album then title.
final artistTracksProvider =
    FutureProvider.family<List<Track>, String>((ref, artistName) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  return dao.byArtist(artistName);
});

/// All tracks of one album; the parameter is the (artist, album) pair so
/// same-named albums by different artists stay apart.
final albumTracksProvider =
    FutureProvider.family<List<Track>, ({String artist, String album})>(
        (ref, params) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  return dao.byAlbum(artist: params.artist, album: params.album);
});

/// All tracks tagged with one genre, ordered by title.
final genreTracksProvider =
    FutureProvider.family<List<Track>, String>((ref, genre) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  return dao.byGenre(genre);
});

/// Distinct artists for the Artists tab (alphabetical).
final artistsProvider = FutureProvider<List<Artist>>((ref) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  return dao.distinctArtists();
});

/// Distinct albums for the Albums tab (newest first).
final albumsProvider = FutureProvider<List<Album>>((ref) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  return dao.distinctAlbums();
});

/// Distinct genre tags for the Genres tab (alphabetical).
final genresProvider = FutureProvider<List<String>>((ref) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  return dao.distinctGenres();
});

/// Total track count of the library (used by the empty states).
final libraryCountProvider = FutureProvider<int>((ref) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  return dao.countAll();
});

/// Persisted scan folders (survives restarts).
final foldersProvider = FutureProvider<List<String>>((ref) async {
  final store = ref.watch(settingsStoreProvider);
  return ScanFoldersStore(store).read();
});

/// UI-facing snapshot of a running (or last finished) library scan.
class ScanUiState {
  /// Idle state (nothing scanned yet in this session).
  const ScanUiState({
    this.scanning = false,
    this.processed = 0,
    this.total = 0,
    this.currentFile = '',
    this.errors = const <String>[],
    this.lastCount = 0,
  });

  /// True while a scan is running.
  final bool scanning;

  /// Files processed so far.
  final int processed;

  /// Files to process in the current scan.
  final int total;

  /// File (or folder) currently being processed.
  final String currentFile;

  /// Error reasons of the current/last scan (capped by
  /// [AppConstants.scanErrorLogLimit]).
  final List<String> errors;

  /// Track count persisted by the last completed scan.
  final int lastCount;

  /// Fraction processed (null → show an indeterminate indicator).
  double? get progress => total <= 0 ? null : processed / total;

  /// Copy with the given fields replaced.
  ScanUiState copyWith({
    bool? scanning,
    int? processed,
    int? total,
    String? currentFile,
    List<String>? errors,
    int? lastCount,
  }) =>
      ScanUiState(
        scanning: scanning ?? this.scanning,
        processed: processed ?? this.processed,
        total: total ?? this.total,
        currentFile: currentFile ?? this.currentFile,
        errors: errors ?? this.errors,
        lastCount: lastCount ?? this.lastCount,
      );
}

/// Callback invoked after a scan completed so that consumers can invalidate
/// the library providers above.
typedef ScanCompletedCallback = void Function();

/// Drives [ScanUiState] from the platform scanner's event stream.
class ScanStateNotifier extends StateNotifier<ScanUiState> {
  /// Creates the notifier; [onScanCompleted] (optional) fires after every
  /// completed scan to refresh library providers.
  ScanStateNotifier({
    required LibraryScanner scanner,
    ScanCompletedCallback? onScanCompleted,
  })  : _scanner = scanner,
        _onScanCompleted = onScanCompleted,
        super(const ScanUiState());

  final LibraryScanner _scanner;
  final ScanCompletedCallback? _onScanCompleted;
  StreamSubscription<ScanEvent>? _subscription;

  /// Starts (or restarts) a scan over [folders].
  void startScan(List<String> folders) {
    if (folders.isEmpty) {
      return;
    }
    unawaited(_subscription?.cancel());
    state = const ScanUiState(scanning: true);
    _subscription = _scanner.scan(folders).listen(
          _handleEvent,
          onError: (Object error) {
            state = state.copyWith(scanning: false);
          },
          onDone: () {
            // A scanner stream that ends without a completion event (e.g. a
            // broken implementation) must not leave the UI spinning.
            if (state.scanning) {
              state = state.copyWith(scanning: false);
            }
          },
        );
  }

  /// Aborts the running scan (if any) without touching persisted folders.
  Future<void> cancel() async {
    await _subscription?.cancel();
    _subscription = null;
    if (state.scanning) {
      state = state.copyWith(scanning: false);
    }
  }

  void _handleEvent(ScanEvent event) {
    switch (event) {
      case ScanStarted():
        state = state.copyWith(
          scanning: true,
          processed: 0,
          total: 0,
          currentFile: event.root,
        );
      case ScanProgress():
        state = state.copyWith(
          processed: event.processed,
          total: event.total,
          currentFile: event.currentFile,
        );
      case ScanError():
        state = state.copyWith(
          errors: <String>[...state.errors, '${event.file}: ${event.reason}'],
        );
      case ScanCompleted():
        state = ScanUiState(
          scanning: false,
          lastCount: event.count,
          errors: event.errors,
          currentFile: state.currentFile,
        );
        _notifyCompleted();
      case TrackFound():
    }
  }

  void _notifyCompleted() {
    try {
      _onScanCompleted?.call();
    } on Object catch (_) {
      // Invalidation must never break the scan lifecycle.
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

/// Live scan progress consumed by the Folders tab.
final scanStateProvider =
    StateNotifierProvider<ScanStateNotifier, ScanUiState>((ref) {
  return ScanStateNotifier(
    scanner: ref.watch(libraryScannerProvider),
    onScanCompleted: () {
      ref.invalidate(tracksPagedProvider);
      ref.invalidate(artistsProvider);
      ref.invalidate(albumsProvider);
      ref.invalidate(genresProvider);
      ref.invalidate(libraryCountProvider);
    },
  );
});

/// Adds [picked] folders to the persisted list and returns the merged list.
Future<List<String>> addScanFolders(WidgetRef ref, List<String> picked) async {
  if (picked.isEmpty) {
    return ref.read(foldersProvider.future);
  }
  final current = await ref.read(foldersProvider.future);
  final merged = <String>{...current, ...picked}.toList();
  final store = ScanFoldersStore(ref.read(settingsStoreProvider));
  await store.write(merged);
  ref.invalidate(foldersProvider);
  return merged;
}

/// Removes [folder] from the persisted list.
Future<void> removeScanFolder(WidgetRef ref, String folder) async {
  final current = await ref.read(foldersProvider.future);
  final merged = current.where((f) => f != folder).toList();
  final store = ScanFoldersStore(ref.read(settingsStoreProvider));
  await store.write(merged);
  ref.invalidate(foldersProvider);
}

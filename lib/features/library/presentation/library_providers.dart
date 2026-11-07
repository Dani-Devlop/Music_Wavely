import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:riverpod/src/providers/future_provider.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/themes/theme_provider.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/library_scanner.dart';
import 'package:wavely/features/library/data/library_scanner_provider.dart';
import 'package:wavely/features/library/data/library_view_config.dart';
import 'package:wavely/features/library/presentation/sort_menu.dart';

/// SQL ORDER BY fragment for a [SortKey] (trusted literals only — the enum
/// guarantees the values; user input never reaches this switch).
String orderBySqlFor(SortKey key) => switch (key) {
      SortKey.titleAsc => 'title COLLATE NOCASE ASC',
      SortKey.titleDesc => 'title COLLATE NOCASE DESC',
      SortKey.artistAsc => 'artist COLLATE NOCASE ASC, title COLLATE NOCASE ASC',
      SortKey.durationAsc => 'duration_ms ASC, title COLLATE NOCASE ASC',
      SortKey.durationDesc =>
        'duration_ms DESC, title COLLATE NOCASE ASC',
      SortKey.dateAddedAsc => 'added_at ASC, id ASC',
      SortKey.dateAddedDesc => 'added_at DESC, id DESC',
      SortKey.playCountDesc =>
        'play_count DESC, title COLLATE NOCASE ASC, id ASC',
      SortKey.trackCountDesc => 'play_count DESC, title COLLATE NOCASE ASC',
    };

/// Resolves the SQL fragment for the Songs tab's current sort.
final songsOrderByProvider = Provider<String>((ref) {
  return orderBySqlFor(ref.watch(sortConfigProvider(LibraryTabId.songs)));
});

/// One page of the library track list, [AppConstants.scrollPageSize] items
/// each, ordered by title (case-folded).
final FutureProviderFamily<List<Track>, int> tracksPagedProvider =
    FutureProvider.family<List<Track>, int>((ref, page) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  final tracks = await dao.getAll(
    limit: AppConstants.scrollPageSize,
    offset: page * AppConstants.scrollPageSize,
  );
  return _applyVisibility(ref, tracks);
});

/// One page of the library track list honoring the Songs tab sort memory.
final FutureProviderFamily<List<Track>, (int page, String orderBy)>
    sortedTracksPagedProvider =
    FutureProvider.family<List<Track>, (int page, String orderBy)>(
        (ref, params) async {
  final (page, orderBy) = params;
  final dao = ref.watch(databaseProvider).tracksDao;
  final tracks = await dao.getAll(
    limit: AppConstants.scrollPageSize,
    offset: page * AppConstants.scrollPageSize,
    orderBy: orderBy,
  );
  return _applyVisibility(ref, tracks);
});

/// One page of the newest additions (Recently Added tab).
final FutureProviderFamily<List<Track>, int> recentlyAddedPagedProvider =
    FutureProvider.family<List<Track>, int>((ref, page) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  final tracks = await dao.recentlyAdded(
    limit: AppConstants.scrollPageSize,
    offset: page * AppConstants.scrollPageSize,
  );
  return _applyVisibility(ref, tracks);
});

/// One page of the most played tracks (Most Played tab).
final FutureProviderFamily<List<Track>, int> mostPlayedPagedProvider =
    FutureProvider.family<List<Track>, int>((ref, page) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  final tracks = await dao.mostPlayed(
    limit: AppConstants.scrollPageSize,
    offset: page * AppConstants.scrollPageSize,
  );
  return _applyVisibility(ref, tracks);
});

/// The distinct non-local source ids (Online tab sections).
final onlineSourcesProvider = FutureProvider<List<String>>((ref) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  return dao.distinctSources();
});

/// Tracks of one non-local source (Online tab rows).
final FutureProviderFamily<List<Track>, String> onlineTracksProvider =
    FutureProvider.family<List<Track>, String>((ref, sourceId) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  final tracks = await dao.bySource(sourceId);
  return _applyVisibility(ref, tracks);
});

/// All playlists with item counts (Playlists tab).
final playlistsProvider = FutureProvider<List<Playlist>>((ref) async {
  final dao = ref.watch(databaseProvider).playlistsDao;
  return dao.getAll();
});

/// Tracks of one playlist in persisted order.
final FutureProviderFamily<List<Track>, int> playlistTracksProvider =
    FutureProvider.family<List<Track>, int>((ref, playlistId) async {
  final dao = ref.watch(databaseProvider).playlistsDao;
  return dao.tracksOf(playlistId);
});

/// Distinct indexed file paths (folder-browser tree).
final libraryFilePathsProvider = FutureProvider<List<String>>((ref) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  return dao.distinctFilePaths();
});

/// Tracks under one folder prefix (folder-browser library view). Path
/// matching happens in memory against the distinct indexed paths so SQL
/// LIKE-wildcard pitfalls (paths containing % or _) never apply.
final FutureProviderFamily<List<Track>, String> folderTracksProvider =
    FutureProvider.family<List<Track>, String>((ref, folder) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  final paths = await ref.watch(libraryFilePathsProvider.future);
  final normalized = LibraryVisibility.normalizePrefix(folder);
  final matching = paths
      .where((path) => path.startsWith(normalized))
      .toList(growable: false);
  final tracks = await dao.byFilePaths(matching);
  return _applyVisibility(ref, tracks);
});

/// Applies the persisted visibility rules (folder blacklist / whitelist,
/// minimum track duration) to [tracks].
List<Track> _applyVisibility(Ref ref, List<Track> tracks) {
  final visibility = ref.watch(libraryVisibilityProvider);
  if (visibility.blacklist.isEmpty &&
      visibility.whitelist.isEmpty &&
      visibility.minDurationSeconds <= 0) {
    return tracks;
  }
  return LibraryVisibility.apply(
    tracks: tracks,
    pathOf: (track) => track.filePath,
    durationMsOf: (track) => track.durationMs,
    blacklist: visibility.blacklist,
    whitelist: visibility.whitelist,
    minDurationSeconds: visibility.minDurationSeconds,
  );
}

/// Persisted visibility rules driving [_applyVisibility].
class LibraryVisibilityConfig {
  const LibraryVisibilityConfig({
    this.blacklist = const <String>[],
    this.whitelist = const <String>[],
    this.minDurationSeconds = 0,
  });

  /// Folders hidden from library views.
  final List<String> blacklist;

  /// When non-empty, ONLY these folders are shown.
  final List<String> whitelist;

  /// Tracks shorter than this many seconds are hidden (0 = off).
  final int minDurationSeconds;
}

/// Hydrates the visibility config and persists every mutation.
class LibraryVisibilityNotifier
    extends StateNotifier<LibraryVisibilityConfig> {
  LibraryVisibilityNotifier(this._store)
      : super(const LibraryVisibilityConfig()) {
    _hydrate();
  }

  final LibraryViewConfigStore _store;

  Future<void> _hydrate() async {
    final blacklist = await _store.readBlacklist();
    final whitelist = await _store.readWhitelist();
    final minDuration = await _store.readMinDurationSeconds();
    if (mounted) {
      state = LibraryVisibilityConfig(
        blacklist: blacklist,
        whitelist: whitelist,
        minDurationSeconds: minDuration,
      );
    }
  }

  /// Replaces the blacklist and persists.
  Future<void> setBlacklist(List<String> folders) async {
    state = LibraryVisibilityConfig(
      blacklist: folders,
      whitelist: state.whitelist,
      minDurationSeconds: state.minDurationSeconds,
    );
    await _store.writeBlacklist(folders);
  }

  /// Replaces the whitelist and persists.
  Future<void> setWhitelist(List<String> folders) async {
    state = LibraryVisibilityConfig(
      blacklist: state.blacklist,
      whitelist: folders,
      minDurationSeconds: state.minDurationSeconds,
    );
    await _store.writeWhitelist(folders);
  }

  /// Sets the minimum track duration (seconds) and persists.
  Future<void> setMinDurationSeconds(int seconds) async {
    state = LibraryVisibilityConfig(
      blacklist: state.blacklist,
      whitelist: state.whitelist,
      minDurationSeconds: seconds,
    );
    await _store.writeMinDurationSeconds(seconds);
  }
}

/// The visibility rules provider (consumed by every library track list).
final libraryVisibilityProvider =
    StateNotifierProvider<LibraryVisibilityNotifier, LibraryVisibilityConfig>(
        (ref) {
  return LibraryVisibilityNotifier(ref.watch(libraryViewConfigStoreProvider));
});

/// Invalidates every library list provider after destructive actions
/// (multi-select delete) or config changes.
void refreshLibraryProviders(Ref ref) {
  ref.invalidate(tracksPagedProvider);
  ref.invalidate(sortedTracksPagedProvider);
  ref.invalidate(recentlyAddedPagedProvider);
  ref.invalidate(mostPlayedPagedProvider);
  ref.invalidate(onlineSourcesProvider);
  ref.invalidate(onlineTracksProvider);
  ref.invalidate(playlistsProvider);
  ref.invalidate(playlistTracksProvider);
  ref.invalidate(libraryFilePathsProvider);
  ref.invalidate(folderTracksProvider);
  ref.invalidate(artistsProvider);
  ref.invalidate(albumsProvider);
  ref.invalidate(genresProvider);
  ref.invalidate(libraryCountProvider);
  ref.invalidate(folderTrackCountsProvider);
}

/// All library tracks of one artist, grouped by album then title.
final FutureProviderFamily<List<Track>, String> artistTracksProvider =
    FutureProvider.family<List<Track>, String>((ref, artistName) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  return dao.byArtist(artistName);
});

/// All tracks of one album; the parameter is the (artist, album) pair so
/// same-named albums by different artists stay apart.
final FutureProviderFamily<List<Track>, ({String album, String artist})> albumTracksProvider =
    FutureProvider.family<List<Track>, ({String artist, String album})>(
        (ref, params) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  return dao.byAlbum(artist: params.artist, album: params.album);
});

/// All tracks tagged with one genre, ordered by title.
final FutureProviderFamily<List<Track>, String> genreTracksProvider =
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

/// The most recently played tracks (Home → "Jump back in"). Empty until
/// the user plays something; refreshed after every scan.
final recentlyPlayedProvider = FutureProvider<List<Track>>((ref) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  return dao.recentlyPlayed();
});

/// Top genres with track counts (Home → quick-mix cards).
final topGenresProvider =
    FutureProvider<List<({String genre, int trackCount})>>((ref) async {
  final dao = ref.watch(databaseProvider).tracksDao;
  return dao.topGenres();
});

/// Track count per persisted scan folder (Folders tab badges). Computed
/// with a LIKE prefix query per folder; the folder list is small.
final folderTrackCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  final folders = await ref.watch(foldersProvider.future);
  final dao = ref.watch(databaseProvider).tracksDao;
  final counts = <String, int>{};
  for (final folder in folders) {
    counts[folder] = await dao.countInFolder(folder);
  }
  return counts;
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
      refreshLibraryProviders(ref);
      ref.invalidate(recentlyPlayedProvider);
      ref.invalidate(topGenresProvider);
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

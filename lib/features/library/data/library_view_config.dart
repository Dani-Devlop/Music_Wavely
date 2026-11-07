import 'dart:convert';

import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/settings/settings_store.dart';

/// Identity of one library tab (Phase 6: nine-tab library).
enum LibraryTabId {
  /// Every track in the library ("Songs").
  songs,

  /// Album grid.
  albums,

  /// Artist grid.
  artists,

  /// Genre grid.
  genres,

  /// Scan-folder manager + folder browser entry point.
  folders,

  /// User-curated playlists.
  playlists,

  /// Tracks sorted by `addedAt`, newest first.
  recentlyAdded,

  /// Tracks sorted by `playCount`, most played first.
  mostPlayed,

  /// Non-local (online / downloaded) tracks grouped by source.
  online,
}

/// Sort orders shared by the library tabs.
enum SortKey {
  /// Title A→Z (default for most tabs).
  titleAsc,

  /// Title Z→A.
  titleDesc,

  /// Artist A→Z.
  artistAsc,

  /// Duration ascending.
  durationAsc,

  /// Duration descending.
  durationDesc,

  /// Date added ascending.
  dateAddedAsc,

  /// Date added descending (default for "Recently Added").
  dateAddedDesc,

  /// Play count, most played first (default for "Most Played").
  playCountDesc,

  /// Track count, largest first (grid tabs).
  trackCountDesc,
}

/// Human label for a [SortKey] inside the sort menu.
String sortKeyLabel(SortKey key) => switch (key) {
      SortKey.titleAsc => 'Title A–Z',
      SortKey.titleDesc => 'Title Z–A',
      SortKey.artistAsc => 'Artist A–Z',
      SortKey.durationAsc => 'Duration (short first)',
      SortKey.durationDesc => 'Duration (long first)',
      SortKey.dateAddedAsc => 'Date added (oldest first)',
      SortKey.dateAddedDesc => 'Date added (newest first)',
      SortKey.playCountDesc => 'Play count',
      SortKey.trackCountDesc => 'Track count',
    };

/// Which sort options a tab exposes (order = menu order).
List<SortKey> sortOptionsFor(LibraryTabId tab) => switch (tab) {
      LibraryTabId.songs ||
      LibraryTabId.recentlyAdded ||
      LibraryTabId.mostPlayed ||
      LibraryTabId.online =>
        <SortKey>[
          SortKey.titleAsc,
          SortKey.titleDesc,
          SortKey.artistAsc,
          SortKey.durationAsc,
          SortKey.durationDesc,
          SortKey.dateAddedAsc,
          SortKey.dateAddedDesc,
          SortKey.playCountDesc,
        ],
      LibraryTabId.albums =>
        <SortKey>[
          SortKey.titleAsc,
          SortKey.titleDesc,
          SortKey.dateAddedDesc,
          SortKey.dateAddedAsc,
          SortKey.trackCountDesc,
        ],
      LibraryTabId.artists ||
      LibraryTabId.genres =>
        <SortKey>[
          SortKey.titleAsc,
          SortKey.titleDesc,
          SortKey.trackCountDesc,
        ],
      LibraryTabId.folders ||
      LibraryTabId.playlists =>
        <SortKey>[
          SortKey.titleAsc,
          SortKey.titleDesc,
          SortKey.dateAddedDesc,
        ],
    };

/// Default [SortKey] per tab.
SortKey defaultSortFor(LibraryTabId tab) => switch (tab) {
      LibraryTabId.recentlyAdded => SortKey.dateAddedDesc,
      LibraryTabId.mostPlayed => SortKey.playCountDesc,
      _ => SortKey.titleAsc,
    };

/// Immutable snapshot of the nine-tab configuration.
class LibraryTabsConfig {
  const LibraryTabsConfig({
    this.order = LibraryTabsConfig.defaultOrder,
    this.hidden = const <LibraryTabId>{},
  });

  /// Spec order: Songs, Albums, Artists, Genres, Folders, Playlists,
  /// Recently Added, Most Played, Online.
  static const List<LibraryTabId> defaultOrder = <LibraryTabId>[
    LibraryTabId.songs,
    LibraryTabId.albums,
    LibraryTabId.artists,
    LibraryTabId.genres,
    LibraryTabId.folders,
    LibraryTabId.playlists,
    LibraryTabId.recentlyAdded,
    LibraryTabId.mostPlayed,
    LibraryTabId.online,
  ];

  /// Visible tabs in display order.
  List<LibraryTabId> get visibleTabs =>
      order.where((tab) => !hidden.contains(tab)).toList(growable: false);

  /// Tab order (all nine tabs).
  final List<LibraryTabId> order;

  /// Hidden (removed from the bar) tabs.
  final Set<LibraryTabId> hidden;

  /// Copy with fields replaced; enforces that at least one tab stays visible.
  LibraryTabsConfig copyWith({
    List<LibraryTabId>? order,
    Set<LibraryTabId>? hidden,
  }) {
    var nextOrder = order ?? this.order;
    var nextHidden = hidden ?? this.hidden;
    // Guard: never allow hiding every tab.
    if (nextOrder.every(nextHidden.contains)) {
      nextHidden = {...nextHidden}..remove(nextOrder.first);
    }
    // Guard: order must contain every enum value exactly once.
    if (nextOrder.length != LibraryTabId.values.length ||
        nextOrder.toSet().length != LibraryTabId.values.length) {
      nextOrder = LibraryTabsConfig.defaultOrder;
    }
    return LibraryTabsConfig(order: nextOrder, hidden: nextHidden);
  }

  /// Serializes to JSON for the settings store.
  String toJson() => jsonEncode(<String, dynamic>{
        'order': <String>[for (final tab in order) tab.name],
        'hidden': <String>[for (final tab in hidden) tab.name],
      });

  /// Parses persisted JSON; corrupt payloads fall back to the defaults so a
  /// broken preference never blocks the library from rendering.
  static LibraryTabsConfig fromJson(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const LibraryTabsConfig();
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final byName = <String, LibraryTabId>{
        for (final tab in LibraryTabId.values) tab.name: tab,
      };
      final order = <LibraryTabId>[
        for (final name in (decoded['order'] as List<dynamic>? ?? const []))
          if (byName[name] case final tab?) tab,
      ];
      final hidden = <LibraryTabId>{
        for (final name in (decoded['hidden'] as List<dynamic>? ?? const []))
          if (byName[name] case final tab?) tab,
      };
      if (order.isEmpty) {
        return LibraryTabsConfig(hidden: hidden);
      }
      return LibraryTabsConfig(order: order, hidden: hidden);
    } on Object catch (_) {
      return const LibraryTabsConfig();
    }
  }
}

/// Persisted library-view preferences: tab layout, per-tab sort keys, the
/// folder blacklist/whitelist and the minimum-track-duration filter.
class LibraryViewConfigStore {
  /// Binds the store to a [SettingsStore] implementation.
  const LibraryViewConfigStore(this._settings);

  static const String _tabsKey =
      '${AppConstants.settingsKeyPrefix}libraryTabs.v1';
  static const String _sortPrefix =
      '${AppConstants.settingsKeyPrefix}librarySort.';
  static const String _blacklistKey =
      '${AppConstants.settingsKeyPrefix}libraryFolderBlacklist';
  static const String _whitelistKey =
      '${AppConstants.settingsKeyPrefix}libraryFolderWhitelist';
  static const String _minDurationKey =
      '${AppConstants.settingsKeyPrefix}libraryMinDurationSeconds';
  static const String _browserModeKey =
      '${AppConstants.settingsKeyPrefix}libraryFolderBrowserMode';

  final SettingsStore _settings;

  // ── Tab layout ────────────────────────────────────────────────────────

  /// Reads the persisted tab layout (order + hidden set).
  Future<LibraryTabsConfig> readTabs() async =>
      LibraryTabsConfig.fromJson(await _settings.read<String>(_tabsKey));

  /// Persists the tab layout.
  Future<void> writeTabs(LibraryTabsConfig config) =>
      _settings.write(_tabsKey, config.toJson());

  // ── Per-tab sort memory ───────────────────────────────────────────────

  /// Reads the sort key persisted for [tab] (falls back to the tab default).
  Future<SortKey> readSort(LibraryTabId tab) async {
    final raw = await _settings.read<String>('$_sortPrefix${tab.name}');
    if (raw == null) {
      return defaultSortFor(tab);
    }
    for (final key in SortKey.values) {
      if (key.name == raw) {
        return key;
      }
    }
    return defaultSortFor(tab);
  }

  /// Persists the sort key for [tab].
  Future<void> writeSort(LibraryTabId tab, SortKey key) =>
      _settings.write('$_sortPrefix${tab.name}', key.name);

  // ── Folder blacklist / whitelist ──────────────────────────────────────

  /// Folders whose tracks are hidden from the library views.
  Future<List<String>> readBlacklist() => _readPaths(_blacklistKey);

  /// Whitelist shortcut (null → "no whitelist", empty is not meaningful).
  Future<List<String>> readWhitelist() => _readPaths(_whitelistKey);

  /// Persists the blacklist.
  Future<void> writeBlacklist(List<String> folders) =>
      _settings.write(_blacklistKey, jsonEncode(folders));

  /// Persists the whitelist.
  Future<void> writeWhitelist(List<String> folders) =>
      _settings.write(_whitelistKey, jsonEncode(folders));

  // ── Minimum track duration ────────────────────────────────────────────

  /// Tracks shorter than this many seconds are hidden from library views
  /// (0 = disabled).
  Future<int> readMinDurationSeconds() async =>
      await _settings.read<int>(_minDurationKey) ?? 0;

  /// Persists the minimum track duration in seconds.
  Future<void> writeMinDurationSeconds(int seconds) =>
      _settings.write(_minDurationKey, seconds);

  // ── Folder browser mode ───────────────────────────────────────────────

  /// Reads the default folder browser mode (`tree` or `library`).
  Future<String> readBrowserMode() async =>
      await _settings.read<String>(_browserModeKey) ?? 'tree';

  /// Persists the default folder browser mode.
  Future<void> writeBrowserMode(String mode) =>
      _settings.write(_browserModeKey, mode);

  Future<List<String>> _readPaths(String key) async {
    final stored = await _settings.read<List<String>>(key);
    if (stored != null) {
      return stored;
    }
    final raw = await _settings.read<String>(key);
    if (raw == null || raw.isEmpty) {
      return const <String>[];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.whereType<String>().toList(growable: false);
    } on Object catch (_) {
      return const <String>[];
    }
  }
}

/// Pure filtering helpers shared by the library providers (blacklist /
/// whitelist / minimum duration). Kept free of Flutter dependencies so the
/// logic is directly unit-testable.
abstract final class LibraryVisibility {
  /// Normalizes [folder] to a prefix that ends with a separator (Windows `\`
  /// and POSIX `/` both accepted) so `/music` does not match `/music-box/…`.
  static String normalizePrefix(String folder) =>
      folder.endsWith('/') || folder.endsWith('\\')
          ? folder
          : '$folder/';

  /// True when [path] lives under any of [prefixes].
  static bool underAny(String path, Iterable<String> prefixes) {
    for (final prefix in prefixes) {
      if (path.startsWith(normalizePrefix(prefix))) {
        return true;
      }
    }
    return false;
  }

  /// Applies the persisted visibility rules to [tracks]:
  /// - blacklist wins over everything;
  /// - when the whitelist is non-empty, only whitelisted folders remain;
  /// - tracks shorter than [minDurationSeconds] (when > 0) are dropped;
  /// - tracks without a file path (remote rows) bypass both folder rules
  ///   (they have no folder to match) but still honor the duration rule.
  static List<T> apply<T>({
    required List<T> tracks,
    required String? Function(T) pathOf,
    required int Function(T) durationMsOf,
    required List<String> blacklist,
    required List<String> whitelist,
    required int minDurationSeconds,
  }) {
    return tracks.where((track) {
      final path = pathOf(track);
      if (blacklist.isNotEmpty && path != null) {
        if (underAny(path, blacklist)) {
          return false;
        }
      }
      if (whitelist.isNotEmpty && path != null) {
        if (!underAny(path, whitelist)) {
          return false;
        }
      }
      if (minDurationSeconds > 0 &&
          durationMsOf(track) < minDurationSeconds * 1000) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }
}

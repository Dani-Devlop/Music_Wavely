/// Phase 6 — unit tests for the library view configuration: tab layout
/// (order/hide/persist), per-tab sort memory and the folder
/// blacklist/whitelist/minimum-duration visibility rules.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/features/library/data/library_view_config.dart';
import 'package:wavely/features/library/presentation/library_tab_manager.dart';

/// Sample row shape for the visibility-filter tests (nullable path covers
/// remote rows without a file path).
typedef SampleRow = ({String? path, int durationMs, String title});

void main() {
  group('LibraryTabsConfig', () {
    test('default order matches the nine-tab spec', () {
      expect(
        LibraryTabsConfig.defaultOrder,
        <LibraryTabId>[
          LibraryTabId.songs,
          LibraryTabId.albums,
          LibraryTabId.artists,
          LibraryTabId.genres,
          LibraryTabId.folders,
          LibraryTabId.playlists,
          LibraryTabId.recentlyAdded,
          LibraryTabId.mostPlayed,
          LibraryTabId.online,
        ],
      );
    });

    test('visibleTabs excludes hidden tabs in order', () {
      const config = LibraryTabsConfig(
        hidden: <LibraryTabId>{LibraryTabId.online, LibraryTabId.genres},
      );
      expect(
        config.visibleTabs,
        <LibraryTabId>[
          LibraryTabId.songs,
          LibraryTabId.albums,
          LibraryTabId.artists,
          LibraryTabId.folders,
          LibraryTabId.playlists,
          LibraryTabId.recentlyAdded,
          LibraryTabId.mostPlayed,
        ],
      );
    });

    test('copyWith never allows hiding every tab', () {
      const config = LibraryTabsConfig();
      final next = config.copyWith(
        hidden: {...LibraryTabId.values},
      );
      expect(next.hidden.contains(next.order.first), isFalse);
      expect(next.visibleTabs, hasLength(1));
    });

    test('copyWith falls back to the default order on a broken order', () {
      const config = LibraryTabsConfig();
      final next = config.copyWith(order: <LibraryTabId>[LibraryTabId.songs]);
      expect(next.order, LibraryTabsConfig.defaultOrder);
    });

    test('JSON roundtrip preserves order and hidden set', () {
      const config = LibraryTabsConfig(
        order: <LibraryTabId>[
          LibraryTabId.playlists,
          LibraryTabId.songs,
          LibraryTabId.albums,
          LibraryTabId.artists,
          LibraryTabId.genres,
          LibraryTabId.folders,
          LibraryTabId.recentlyAdded,
          LibraryTabId.mostPlayed,
          LibraryTabId.online,
        ],
        hidden: <LibraryTabId>{LibraryTabId.online},
      );
      final restored = LibraryTabsConfig.fromJson(config.toJson());
      expect(restored.order, config.order);
      expect(restored.hidden, config.hidden);
    });

    test('fromJson tolerates corrupt payloads', () {
      expect(LibraryTabsConfig.fromJson(null), const LibraryTabsConfig());
      expect(LibraryTabsConfig.fromJson(''), const LibraryTabsConfig());
      expect(
        LibraryTabsConfig.fromJson('not json at all'),
        const LibraryTabsConfig(),
      );
      // Unknown tab names are dropped, not thrown.
      final partial = LibraryTabsConfig.fromJson(
        '{"order": ["songs", "bogus"], "hidden": ["online"]}',
      );
      expect(partial.order.first, LibraryTabId.songs);
      expect(partial.hidden, contains(LibraryTabId.online));
    });
  });

  group('LibraryTabsNotifier (persistence)', () {
    test('reorder persists and applies ReorderableListView semantics',
        () async {
      final store = LibraryViewConfigStore(InMemorySettingsStore());
      final notifier = LibraryTabsNotifier(store);
      // Hydration is async; flush microtasks.
      await Future<void>.delayed(Duration.zero);

      // Move Songs (index 0) after Albums (ReorderableListView semantics:
      // newIndex 2 collapses to target 1).
      await notifier.reorder(0, 2);
      expect(notifier.state.order.take(2),
          <LibraryTabId>[LibraryTabId.albums, LibraryTabId.songs]);

      // A fresh notifier hydrates the persisted order.
      final reloaded = LibraryTabsNotifier(store);
      await Future<void>.delayed(Duration.zero);
      expect(reloaded.state.order.take(2),
          <LibraryTabId>[LibraryTabId.albums, LibraryTabId.songs]);
    });

    test('toggleHidden persists visibility and guards the last tab',
        () async {
      final store = LibraryViewConfigStore(InMemorySettingsStore());
      final notifier = LibraryTabsNotifier(store);
      await Future<void>.delayed(Duration.zero);

      await notifier.toggleHidden(LibraryTabId.online);
      expect(notifier.state.hidden, contains(LibraryTabId.online));
      await notifier.toggleHidden(LibraryTabId.online);
      expect(notifier.state.hidden, isNot(contains(LibraryTabId.online)));

      // Hiding everything keeps one tab visible.
      for (final tab in LibraryTabId.values) {
        await notifier.toggleHidden(tab);
      }
      expect(notifier.state.visibleTabs, hasLength(1));
    });

    test('resetToDefault restores the spec layout', () async {
      final store = LibraryViewConfigStore(InMemorySettingsStore());
      final notifier = LibraryTabsNotifier(store);
      await Future<void>.delayed(Duration.zero);

      await notifier.toggleHidden(LibraryTabId.songs);
      await notifier.resetToDefault();
      expect(notifier.state.hidden, isEmpty);
      expect(notifier.state.order, LibraryTabsConfig.defaultOrder);
    });
  });

  group('Sort memory', () {
    test('readSort falls back to per-tab defaults', () async {
      final store = LibraryViewConfigStore(InMemorySettingsStore());
      expect(
        await store.readSort(LibraryTabId.songs),
        SortKey.titleAsc,
      );
      expect(
        await store.readSort(LibraryTabId.recentlyAdded),
        SortKey.dateAddedDesc,
      );
      expect(
        await store.readSort(LibraryTabId.mostPlayed),
        SortKey.playCountDesc,
      );
    });

    test('writeSort + readSort roundtrip per tab', () async {
      final store = LibraryViewConfigStore(InMemorySettingsStore());
      await store.writeSort(LibraryTabId.songs, SortKey.durationDesc);
      await store.writeSort(LibraryTabId.albums, SortKey.trackCountDesc);
      expect(
        await store.readSort(LibraryTabId.songs),
        SortKey.durationDesc,
      );
      expect(
        await store.readSort(LibraryTabId.albums),
        SortKey.trackCountDesc,
      );
      // Other tabs keep their defaults.
      expect(
        await store.readSort(LibraryTabId.playlists),
        SortKey.titleAsc,
      );
    });
  });

  group('LibraryVisibility.apply (folder blacklist / whitelist / duration)',
      () {
    List<SampleRow> sampleRows() =>
        <SampleRow>[
          (path: '/music/rock/a.mp3', durationMs: 180000, title: 'a'),
          (path: '/music/pop/b.mp3', durationMs: 180000, title: 'b'),
          // A folder that SHARES the /music prefix but is not /music-box.
          (path: '/music-box/c.mp3', durationMs: 180000, title: 'c'),
          (path: '/music/rock/short.mp3', durationMs: 2000, title: 'short'),
          (path: null, durationMs: 180000, title: 'remote'),
        ];

    test('empty rules keep every track', () {
      final rows = sampleRows();
      expect(
        LibraryVisibility.apply(
          tracks: rows,
          pathOf: (SampleRow row) => row.path,
          durationMsOf: (SampleRow row) => row.durationMs,
          blacklist: const <String>[],
          whitelist: const <String>[],
          minDurationSeconds: 0,
        ),
        hasLength(5),
      );
    });

    test('blacklist hides the folder subtree without prefix collisions',
        () {
      final rows = sampleRows();
      final visible = LibraryVisibility.apply(
        tracks: rows,
        pathOf: (SampleRow row) => row.path,
        durationMsOf: (SampleRow row) => row.durationMs,
        blacklist: <String>['/music/rock'],
        whitelist: const <String>[],
        minDurationSeconds: 0,
      );
      // /music/rock/* hidden, everything else stays (including /music-box).
      expect(visible.map((row) => row.title), <String>['b', 'c', 'remote']);
    });

    test('blacklist matches subfolders at any depth', () {
      final rows = sampleRows();
      final visible = LibraryVisibility.apply(
        tracks: rows,
        pathOf: (SampleRow row) => row.path,
        durationMsOf: (SampleRow row) => row.durationMs,
        blacklist: <String>['/music/rock/'],
        whitelist: const <String>[],
        minDurationSeconds: 0,
      );
      expect(visible.map((row) => row.title), <String>['b', 'c', 'remote']);
    });

    test('whitelist restricts to the allowed folders when non-empty', () {
      final rows = sampleRows();
      final visible = LibraryVisibility.apply(
        tracks: rows,
        pathOf: (SampleRow row) => row.path,
        durationMsOf: (SampleRow row) => row.durationMs,
        blacklist: const <String>[],
        whitelist: <String>['/music/pop'],
        minDurationSeconds: 0,
      );
      // Pathless (remote) rows bypass the whitelist so the Online tab
      // survives a local whitelist.
      expect(visible.map((row) => row.title), <String>['b', 'remote']);
    });

    test('minimum duration filter drops short tracks', () {
      final rows = sampleRows();
      final visible = LibraryVisibility.apply(
        tracks: rows,
        pathOf: (SampleRow row) => row.path,
        durationMsOf: (SampleRow row) => row.durationMs,
        blacklist: const <String>[],
        whitelist: const <String>[],
        minDurationSeconds: 10,
      );
      expect(visible.map((row) => row.title),
          <String>['a', 'b', 'c', 'remote']);
    });

    test('blacklist wins over whitelist', () {
      final rows = sampleRows();
      final visible = LibraryVisibility.apply(
        tracks: rows,
        pathOf: (SampleRow row) => row.path,
        durationMsOf: (SampleRow row) => row.durationMs,
        blacklist: <String>['/music/pop'],
        whitelist: <String>['/music'],
        minDurationSeconds: 0,
      );
      // b: blacklisted; c (/music-box): not whitelisted; short: kept
      // (min duration off); remote: bypasses folder rules.
      expect(visible.map((row) => row.title),
          <String>['a', 'short', 'remote']);
    });

    test('tracks without a path (remote) bypass folder rules but honor '
        'duration', () {
      final rows = sampleRows();
      final visible = LibraryVisibility.apply(
        tracks: rows,
        pathOf: (SampleRow row) => row.path,
        durationMsOf: (SampleRow row) => row.durationMs,
        blacklist: <String>['/music'],
        whitelist: const <String>[],
        minDurationSeconds: 5,
      );
      // Remote rows ignore folder rules; /music-box survives the /music
      // blacklist (prefix-safe matching); the 2s short track is dropped.
      expect(visible.map((row) => row.title), <String>['c', 'remote']);
    });
  });

  group('LibraryViewConfigStore (filters persistence)', () {
    test('blacklist and whitelist roundtrip', () async {
      final store = LibraryViewConfigStore(InMemorySettingsStore());
      expect(await store.readBlacklist(), isEmpty);
      expect(await store.readWhitelist(), isEmpty);

      await store.writeBlacklist(<String>['/music/rock', 'D:\\Private']);
      await store.writeWhitelist(<String>['/music']);
      expect(await store.readBlacklist(),
          <String>['/music/rock', 'D:\\Private']);
      expect(await store.readWhitelist(), <String>['/music']);
    });

    test('min duration + browser mode roundtrip with defaults', () async {
      final store = LibraryViewConfigStore(InMemorySettingsStore());
      expect(await store.readMinDurationSeconds(), 0);
      expect(await store.readBrowserMode(), 'tree');

      await store.writeMinDurationSeconds(15);
      await store.writeBrowserMode('library');
      expect(await store.readMinDurationSeconds(), 15);
      expect(await store.readBrowserMode(), 'library');
    });
  });
}

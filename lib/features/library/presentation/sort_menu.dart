import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/library/data/library_view_config.dart';

/// Sort-key store per library tab (sorting memory, Phase 6). Each tab gets
/// its own notifier; every change is persisted through
/// [LibraryViewConfigStore] so the user's choice survives restarts.
class SortConfigNotifier extends StateNotifier<SortKey> {
  SortConfigNotifier(this._store, this._tab, SortKey initial) : super(initial) {
    _hydrate();
  }

  final LibraryViewConfigStore _store;
  final LibraryTabId _tab;

  Future<void> _hydrate() async {
    final persisted = await _store.readSort(_tab);
    if (mounted && persisted != state) {
      state = persisted;
    }
  }

  /// Persists [key] and applies it immediately.
  Future<void> select(SortKey key) async {
    state = key;
    await _store.writeSort(_tab, key);
  }
}

/// Family: one sort config per [LibraryTabId].
final sortConfigProvider = StateNotifierProvider.autoDispose
    .family<SortConfigNotifier, SortKey, LibraryTabId>(
  (ref, tab) {
    final store = ref.watch(libraryViewConfigStoreProvider);
    return SortConfigNotifier(store, tab, defaultSortFor(tab));
  },
);

/// The shared config-store binding (overridden in tests with an
/// [InMemorySettingsStore]-backed instance).
final libraryViewConfigStoreProvider =
    Provider<LibraryViewConfigStore>((ref) {
  return LibraryViewConfigStore(ref.watch(settingsStoreProvider));
});

/// Sort icon button that opens the option sheet for [tab]. Reads and writes
/// [sortConfigProvider].
class SortMenuButton extends ConsumerWidget {
  /// Creates the sort menu button.
  const SortMenuButton({required this.tab, super.key});

  final LibraryTabId tab;

  Future<void> _openSheet(BuildContext context, WidgetRef ref) async {
    final colors = context.wavelyColors;
    final options = sortOptionsFor(tab);
    final current = ref.read(sortConfigProvider(tab));
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Text(
                'Sort by',
                style: WavelyTypography.title20(color: colors.textPrimary),
              ),
            ),
            for (final option in options)
              ListTile(
                key: ValueKey<String>('sort-option-${option.name}'),
                leading: SizedBox(
                  width: 24,
                  child: option == current
                      ? Icon(
                          Icons.check,
                          color: colors.accentColors.accent,
                        )
                      : null,
                ),
                title: Text(
                  sortKeyLabel(option),
                  style: WavelyTypography.body14(
                    color: option == current
                        ? colors.accentColors.accent
                        : colors.textPrimary,
                  ),
                ),
                onTap: () {
                  ref.read(sortConfigProvider(tab).notifier).select(option);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: Spacing.md),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(sortConfigProvider(tab));
    return IconButton(
      key: ValueKey<String>('sort-menu-${tab.name}'),
      icon: const Icon(Icons.sort),
      tooltip: 'Sort by ${sortKeyLabel(current)}',
      onPressed: () => _openSheet(context, ref),
    );
  }
}

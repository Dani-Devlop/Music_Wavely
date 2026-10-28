import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/downloads/data/download_service.dart';
import 'package:wavely/features/downloads/data/downloads_providers.dart';
import 'package:wavely/features/search/domain/search_service.dart';
import 'package:wavely/sources/source_providers.dart';

/// Debounce constant shared with the local search screen behaviour.
const Duration _kOnlineDebounce = Duration(milliseconds: 300);

/// UI state of the online (unified) search pane.
class OnlineSearchState {
  /// Creates the state.
  const OnlineSearchState({
    this.query = '',
    this.loading = false,
    this.hits = const <UnifiedSearchHit>[],
    this.failedSources = const <String>[],
    this.error,
  });

  /// Query the state belongs to.
  final String query;

  /// True while a search round is in flight.
  final bool loading;

  /// Merged + deduped hits.
  final List<UnifiedSearchHit> hits;

  /// Sources that failed or timed out during the round.
  final List<String> failedSources;

  /// Fatal error (search service unavailable).
  final String? error;

  /// Copy with replaced fields.
  OnlineSearchState copyWith({
    String? query,
    bool? loading,
    List<UnifiedSearchHit>? hits,
    List<String>? failedSources,
    String? error,
  }) =>
      OnlineSearchState(
        query: query ?? this.query,
        loading: loading ?? this.loading,
        hits: hits ?? this.hits,
        failedSources: failedSources ?? this.failedSources,
        error: error,
      );
}

/// Debounces queries and runs the unified [SearchService].
class OnlineSearchController extends StateNotifier<OnlineSearchState> {
  /// Creates the controller over the (future) service.
  OnlineSearchController(this._service) : super(const OnlineSearchState());

  final Future<SearchService?> _service;
  Timer? _debounce;

  /// Called on every keystroke.
  void onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      _debounce = null;
      state = const OnlineSearchState();
      return;
    }
    _debounce = Timer(_kOnlineDebounce, () {
      unawaited(_run(query));
    });
  }

  Future<void> _run(String query) async {
    state = state.copyWith(query: query, loading: true, error: null);
    try {
      final SearchService? service = await _service;
      if (service == null) {
        state = state.copyWith(
          loading: false,
          error: 'No online sources are enabled.',
        );
        return;
      }
      final UnifiedSearchResult result = await service.search(query);
      if (state.query != query) {
        return;
      }
      state = OnlineSearchState(
        query: query,
        hits: result.hits,
        failedSources: result.failedSources,
      );
    } on Object catch (e) {
      if (state.query != query) {
        return;
      }
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

/// Builds the [SearchService] over the currently enabled sources.
final onlineSearchServiceProvider = FutureProvider<SearchService?>((ref) async {
  final sources = await ref.watch(enabledSourcesProvider.future);
  if (sources.isEmpty) {
    return null;
  }
  return SearchService(sources: sources);
});

/// Controller provider (recreated when the service changes).
final onlineSearchControllerProvider =
    StateNotifierProvider<OnlineSearchController, OnlineSearchState>((ref) {
  return OnlineSearchController(ref.watch(onlineSearchServiceProvider.future));
});

/// Results pane of the unified online search: source badge + quality badge
/// per row; tapping a row enqueues a download.
class OnlineSearchPane extends ConsumerStatefulWidget {
  /// Creates the pane.
  const OnlineSearchPane({super.key});

  @override
  ConsumerState<OnlineSearchPane> createState() => _OnlineSearchPaneState();
}

class _OnlineSearchPaneState extends ConsumerState<OnlineSearchPane> {
  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final OnlineSearchState state =
        ref.watch(onlineSearchControllerProvider);
    if (state.loading) {
      return ListView.builder(
        padding: const EdgeInsets.all(Spacing.lg),
        itemCount: 5,
        itemBuilder: (BuildContext context, int index) => const Padding(
          padding: EdgeInsets.only(bottom: Spacing.sm),
          child: ShimmerBox(height: 56),
        ),
      );
    }
    if (state.error != null) {
      return Center(
        child: Text(
          state.error!,
          style: TextStyle(color: colors.textSecondary),
        ),
      );
    }
    if (state.query.isEmpty) {
      return Center(
        child: Text(
          'Search legal online sources',
          style: TextStyle(color: colors.textTertiary),
        ),
      );
    }
    if (state.hits.isEmpty) {
      return Center(
        child: Text(
          'No online results for "${state.query}"',
          style: TextStyle(color: colors.textTertiary),
        ),
      );
    }
    return Column(
      children: <Widget>[
        if (state.failedSources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: Text(
              'Some sources failed: ${state.failedSources.join(', ')}',
              style: TextStyle(color: colors.textTertiary),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(Spacing.lg),
            itemCount: state.hits.length,
            itemBuilder: (BuildContext context, int index) {
              final UnifiedSearchHit hit = state.hits[index];
              return ListTile(
                key: ValueKey('online-hit-${hit.track.sourceTrackId}'),
                leading: SourceBadge(sourceId: hit.track.sourceId),
                title: Text(
                  hit.track.title,
                  style: TextStyle(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${hit.track.artistOrUnknown} · ${hit.qualityLabel}',
                  style: TextStyle(color: colors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  key: ValueKey(
                    'download-online-${hit.track.sourceTrackId}',
                  ),
                  tooltip: 'Download',
                  icon: const Icon(Icons.download_rounded),
                  onPressed: () => _enqueue(context, ref, hit),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _enqueue(
    BuildContext context,
    WidgetRef ref,
    UnifiedSearchHit hit,
  ) async {
    final AsyncValue<DownloadService> service =
        ref.read(downloadServiceProvider);
    final DownloadService? s = service.asData?.value;
    if (s == null) {
      return;
    }
    await s.enqueue(hit.track);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Queued: ${hit.track.title}')),
      );
    }
  }
}

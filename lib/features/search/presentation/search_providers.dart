import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/extensions/string_x.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/domain/usecases/search_local.dart';

/// Search usecase bound to the library database.
final searchLocalProvider = Provider<SearchLocal>((ref) {
  return SearchLocal(ref.watch(databaseProvider).tracksDao);
});

/// Immutable UI state of the search screen.
class SearchUiState {
  /// Idle/blank state (no query typed yet).
  const SearchUiState({
    this.query = '',
    this.loading = false,
    this.results = const SearchResults(),
    this.error,
  });

  /// Query the current state belongs to.
  final String query;

  /// True while a debounced search is in flight.
  final bool loading;

  /// Results of the last completed search for [query].
  final SearchResults results;

  /// Failure reason of the last search, if any.
  final String? error;

  /// Copy with the given fields replaced.
  SearchUiState copyWith({
    String? query,
    bool? loading,
    SearchResults? results,
    String? error,
  }) =>
      SearchUiState(
        query: query ?? this.query,
        loading: loading ?? this.loading,
        results: results ?? this.results,
        error: error,
      );
}

/// Debounces the query box and runs [SearchLocal], keeping [SearchUiState]
/// fresh (stale responses of superseded queries are dropped).
class SearchResultsController extends StateNotifier<SearchUiState> {
  /// Creates the controller over the [SearchLocal] usecase.
  SearchResultsController(this._searchLocal) : super(const SearchUiState());

  final SearchLocal _searchLocal;
  Timer? _debounce;

  /// Called on every keystroke; restarts the debounce timer.
  void onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      _debounce = null;
      state = const SearchUiState();
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: AppConstants.searchDebounceMs),
      () {
        unawaited(_runSearch(query));
      },
    );
  }

  /// Re-runs the current query (used by the error state's retry button).
  void retry() {
    final query = state.query;
    if (query.isNotBlank) {
      unawaited(_runSearch(query));
    }
  }

  Future<void> _runSearch(String query) async {
    state = state.copyWith(query: query, loading: true, error: null);
    try {
      final results = await _searchLocal(query);
      if (state.query != query) {
        return;
      }
      state = SearchUiState(query: query, results: results);
    } on Object catch (error) {
      if (state.query != query) {
        return;
      }
      state = SearchUiState(query: query, error: error.toString());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

/// Live search state consumed by the search screen.
final searchResultsControllerProvider =
    StateNotifierProvider<SearchResultsController, SearchUiState>((ref) {
  return SearchResultsController(ref.watch(searchLocalProvider));
});

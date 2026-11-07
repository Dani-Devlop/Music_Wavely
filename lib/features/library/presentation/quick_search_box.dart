import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/design_system/design_system.dart';

/// Persistent quick-search input anchored at the bottom of every library
/// list (Phase 6). Filters the host list in real time via [onQueryChanged]
/// (case-folded contains matching is up to the host — the box only owns the
/// text field, its debounce and the clear affordance).
class QuickSearchBox extends StatefulWidget {
  /// Creates the quick search box; [onQueryChanged] receives the trimmed
  /// query on every keystroke (debounced by
  /// [AppConstants.searchDebounceMs]).
  const QuickSearchBox({
    required this.onQueryChanged,
    this.hintText = 'Filter…',
    this.filterKey,
    super.key,
  });

  /// Invoked with the (possibly empty) query as the user types.
  final ValueChanged<String> onQueryChanged;

  /// Placeholder text.
  final String hintText;

  /// Optional key override (tests target specific boxes).
  final Key? filterKey;

  @override
  State<QuickSearchBox> createState() => _QuickSearchBoxState();
}

class _QuickSearchBoxState extends State<QuickSearchBox> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: AppConstants.searchDebounceMs),
      () {
        if (mounted) {
          widget.onQueryChanged(_controller.text.trim().toLowerCase());
        }
      },
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.xs,
        Spacing.lg,
        Spacing.sm,
      ),
      child: TextField(
        key: widget.filterKey ?? const ValueKey<String>('quick-search-field'),
        controller: _controller,
        style: WavelyTypography.body14(color: colors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.filter_list, color: colors.textTertiary),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  key: const ValueKey<String>('quick-search-clear'),
                  icon: Icon(Icons.close, size: 18, color: colors.textTertiary),
                  tooltip: 'Clear filter',
                  onPressed: () {
                    _controller.clear();
                    widget.onQueryChanged('');
                  },
                ),
          hintText: widget.hintText,
          hintStyle: WavelyTypography.caption12(color: colors.textTertiary),
          filled: true,
          fillColor: colors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: colors.borderGlass),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: colors.borderGlass),
          ),
        ),
      ),
    );
  }
}

/// Case-folded "contains" matcher shared by every list host so the
/// QuickSearch filtering behaves identically across tabs.
bool quickSearchMatches(String? haystack, String query) {
  if (query.isEmpty) {
    return true;
  }
  if (haystack == null) {
    return false;
  }
  return haystack.toLowerCase().contains(query);
}

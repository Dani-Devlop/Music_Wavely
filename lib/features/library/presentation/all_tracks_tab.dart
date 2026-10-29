import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';

/// Vertical distance (logical px) at which the next page starts loading.
const double _loadMoreThreshold = 400;

/// Height of the placeholder rows shown while the first page loads.
const double _shimmerRowHeight = 56;

/// Number of placeholder rows shown while the first page loads.
const int _shimmerRowCount = 8;

/// All-tracks tab: infinite, paged list of every track in the library.
class AllTracksTab extends ConsumerStatefulWidget {
  /// Creates the all-tracks tab.
  const AllTracksTab({super.key});

  @override
  ConsumerState<AllTracksTab> createState() => _AllTracksTabState();
}

class _AllTracksTabState extends ConsumerState<AllTracksTab> {
  final List<Track> _tracks = <Track>[];
  int _nextPage = 0;
  bool _loading = false;
  bool _initialLoaded = false;
  bool _canLoadMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    if (_loading || !_canLoadMore) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(tracksPagedProvider(_nextPage).future);
      if (!mounted) {
        return;
      }
      setState(() {
        _tracks.addAll(page);
        _nextPage++;
        _loading = false;
        _initialLoaded = true;
        _canLoadMore = page.length == AppConstants.scrollPageSize;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _initialLoaded = true;
        _error = error.toString();
      });
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.metrics.extentAfter < _loadMoreThreshold &&
        _canLoadMore &&
        !_loading) {
      unawaited(_loadMore());
    }
    return false;
  }

  void _playFrom(int index) {
    unawaited(
      ref
          .read(trackLauncherProvider)
          .playTracks(List<Track>.of(_tracks), startIndex: index),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialLoaded) {
      return ListView.builder(
        padding: const EdgeInsets.all(Spacing.lg),
        itemCount: _shimmerRowCount,
        itemBuilder: (context, index) => const Padding(
          padding: EdgeInsets.only(bottom: Spacing.sm),
          child: ShimmerBox(height: _shimmerRowHeight),
        ),
      );
    }
    if (_error != null && _tracks.isEmpty) {
      return ErrorState(
        message: 'Could not load your library',
        detail: _error,
        onRetry: () {
          unawaited(_loadMore());
        },
      );
    }
    if (_tracks.isEmpty) {
      return EmptyState(
        icon: Icons.library_music,
        title: 'No music yet',
        subtitle: 'Add a folder in the Folders tab to start scanning.',
        ctaLabel: 'Open Folders',
        onCta: _openFoldersTab,
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        itemCount: _tracks.length + (_loading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _tracks.length) {
            return const Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final track = _tracks[index];
          return TrackTile(
            key: ValueKey<String>('all-track-${track.id}'),
            track: track,
            showSourceBadge: true,
            onTap: () {
              _playFrom(index);
            },
          );
        },
      ),
    );
  }

  void _openFoldersTab() {
    final controller = DefaultTabController.maybeOf(context);
    if (controller != null) {
      controller.animateTo(0);
    }
  }
}

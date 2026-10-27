import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/domain/entities/entities.dart';

/// Configuration of the advanced shuffle pipeline (Stage 1.2, B7).
///
/// All filters are optional; empty allow-lists mean "no restriction" while a
/// non-empty blocked list always excludes. [weighting] interpolates between
/// uniform randomness (0.0) and play-count-weighted bias (1.0).
class ShuffleConfig {
  const ShuffleConfig({
    this.allowedLanguages = const <String>{},
    this.blockedLanguages = const <String>{},
    this.allowedGenres = const <String>{},
    this.blockedGenres = const <String>{},
    this.allowedArtistIds = const <String>{},
    this.blockedArtistIds = const <String>{},
    this.includeExplicit = true,
    this.weighting = 0,
    this.noRepeatWindow = AppConstants.shuffleNoRepeatWindow,
    this.seed,
  });

  final Set<String> allowedLanguages;
  final Set<String> blockedLanguages;
  final Set<String> allowedGenres;
  final Set<String> blockedGenres;
  final Set<String> allowedArtistIds;
  final Set<String> blockedArtistIds;
  final bool includeExplicit;

  /// 0.0 = uniform shuffle, 1.0 = strongly biased towards play counts.
  final double weighting;

  final int noRepeatWindow;

  /// Fixed seed for deterministic tests; null → time-based.
  final int? seed;

  Map<String, Object?> toJson() => <String, Object?>{
        'allowedLanguages': allowedLanguages.toList(),
        'blockedLanguages': blockedLanguages.toList(),
        'allowedGenres': allowedGenres.toList(),
        'blockedGenres': blockedGenres.toList(),
        'allowedArtistIds': allowedArtistIds.toList(),
        'blockedArtistIds': blockedArtistIds.toList(),
        'includeExplicit': includeExplicit,
        'weighting': weighting,
        'noRepeatWindow': noRepeatWindow,
      };

  static ShuffleConfig fromJson(Map<String, Object?> json) => ShuffleConfig(
        allowedLanguages: _strings(json['allowedLanguages']),
        blockedLanguages: _strings(json['blockedLanguages']),
        allowedGenres: _strings(json['allowedGenres']),
        blockedGenres: _strings(json['blockedGenres']),
        allowedArtistIds: _strings(json['allowedArtistIds']),
        blockedArtistIds: _strings(json['blockedArtistIds']),
        includeExplicit: (json['includeExplicit'] as bool?) ?? true,
        weighting: ((json['weighting'] as num?) ?? 0).toDouble().clamp(0, 1),
        noRepeatWindow:
            ((json['noRepeatWindow'] as num?) ?? AppConstants.shuffleNoRepeatWindow)
                .toInt(),
      );

  static Set<String> _strings(Object? raw) =>
      (raw as List<Object?>?)?.whereType<String>().toSet() ?? <String>{};
}

/// Stage 1.2 advanced shuffle pipeline:
/// pool → filters → weights → seeded weighted sort → anchor current →
/// no-repeat window.
class AdvancedShuffle {
  const AdvancedShuffle();

  /// Returns the shuffled sublist (never mutates [pool]). The currently
  /// playing track ([currentIndex]) always becomes the first element, even
  /// when filters would exclude it — playback must never be interrupted by
  /// its own shuffle config.
  List<Track> shuffle(
    List<Track> pool, {
    int? currentIndex,
    required ShuffleConfig config,
    List<int> recentlyPlayedIds = const <int>[],
  }) {
    final candidates = _filter(pool, config);
    final current = (currentIndex != null &&
            currentIndex >= 0 &&
            currentIndex < pool.length)
        ? pool[currentIndex]
        : null;
    if (candidates.length <= 1) {
      return current == null
          ? List<Track>.of(candidates)
          : <Track>[current, ...candidates.where((t) => t != current)];
    }
    final weighted = _weightedOrder(candidates, config);
    final withAnchor = <Track>[
      if (current != null) ...<Track>[current],
      ...weighted.where((t) => t != current),
    ];
    _applyNoRepeatWindow(withAnchor, recentlyPlayedIds.toSet(),
        window: config.noRepeatWindow);
    return withAnchor;
  }

  List<Track> _filter(List<Track> pool, ShuffleConfig config) => pool
      .where((t) => _passes(t, config))
      .toList(growable: false);

  bool _passes(Track t, ShuffleConfig config) {
    final language = (t.language ?? '').toLowerCase();
    if (language.isNotEmpty) {
      if (config.blockedLanguages.contains(language)) {
        return false;
      }
      if (config.allowedLanguages.isNotEmpty &&
          !config.allowedLanguages.contains(language)) {
        return false;
      }
    }
    final genre = (t.genre ?? '').toLowerCase();
    if (genre.isNotEmpty) {
      if (config.blockedGenres.contains(genre)) {
        return false;
      }
      if (config.allowedGenres.isNotEmpty &&
          !config.allowedGenres.contains(genre)) {
        return false;
      }
    }
    final artist = t.artist.toLowerCase();
    if (config.blockedArtistIds.contains(artist)) {
      return false;
    }
    if (config.allowedArtistIds.isNotEmpty &&
        !config.allowedArtistIds.contains(artist)) {
      return false;
    }
    if (!config.includeExplicit && t.explicit) {
      return false;
    }
    return true;
  }

  /// Weighted random ordering: key = pow(rng, 1 / weight), sorted desc
  /// (uniform when weighting == 0 since every weight is 1).
  List<Track> _weightedOrder(List<Track> candidates, ShuffleConfig config) {
    final rng = Random(config.seed ?? DateTime.now().microsecondsSinceEpoch);
    final maxPlays = candidates.fold<int>(0, (m, t) => max(m, t.playCount));
    final keyed = <(double, Track)>[
      for (final t in candidates)
        (
          _key(rng, t, config.weighting, maxPlays),
          t,
        ),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return <Track>[for (final entry in keyed) entry.$2];
  }

  double _key(Random rng, Track t, double weighting, int maxPlays) {
    final roll = rng.nextDouble();
    if (weighting <= 0 || maxPlays == 0) {
      return roll;
    }
    final weight = 1.0 + weighting * (t.playCount / maxPlays);
    return pow(roll, 1 / weight).toDouble();
  }

  /// Pushes recently played ids out of the first [window] slots (after the
  /// anchored current track) by swapping with fresh tail candidates.
  void _applyNoRepeatWindow(
    List<Track> result,
    Set<int> recentIds, {
    required int window,
  }) {
    if (recentIds.isEmpty) {
      return;
    }
    final windowEnd = min(window, result.length);
    for (var i = 1; i < windowEnd; i++) {
      final id = result[i].id;
      if (id == null || !recentIds.contains(id)) {
        continue;
      }
      for (var j = result.length - 1; j >= windowEnd; j--) {
        final candidateId = result[j].id;
        if (candidateId == null || !recentIds.contains(candidateId)) {
          final tmp = result[i];
          result[i] = result[j];
          result[j] = tmp;
          break;
        }
      }
    }
  }
}

/// Persists the [ShuffleConfig] as JSON under one prefs key and exposes it to
/// the queue layer (composition root reads it inside the shuffle resolver).
final advancedShuffleConfigProvider =
    StateNotifierProvider<ShuffleConfigNotifier, ShuffleConfig>(
  (ref) => throw UnimplementedError(
    'advancedShuffleConfigProvider must be overridden with the bootstrap '
    'SharedPreferences instance (see buildOverrides)',
  ),
);

class ShuffleConfigNotifier extends StateNotifier<ShuffleConfig> {
  ShuffleConfigNotifier(this._prefs) : super(_load(_prefs));

  static const String prefsKey = 'wavely.shuffle.config';

  final SharedPreferences _prefs;

  static ShuffleConfig _load(SharedPreferences prefs) {
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) {
      return const ShuffleConfig();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return ShuffleConfig.fromJson(decoded);
      }
    } on Object catch (_) {
      // Corrupt payload — fall back to defaults.
    }
    return const ShuffleConfig();
  }

  void update(ShuffleConfig config) {
    state = config;
    unawaited(_prefs.setString(prefsKey, jsonEncode(state.toJson())));
  }
}

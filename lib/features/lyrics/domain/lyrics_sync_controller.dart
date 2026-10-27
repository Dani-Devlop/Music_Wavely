import 'dart:async';

import 'package:wavely/domain/entities/entities.dart';

/// Tracks which lyric line is active for a given playback position.
///
/// Feeds on the engine position stream and emits the active line index
/// (`-1` before the first line starts). Consecutive identical indices are
/// deduplicated; backwards seeks are handled by re-scanning from the top,
/// so seeking to an earlier position always lands on the correct line.
class LyricsSyncController {
  LyricsSyncController({
    required List<LyricLine> lines,
    required Stream<Duration> positionStream,
  }) : _lines = lines {
    _sub = positionStream.listen(_onPosition);
  }

  final List<LyricLine> _lines;
  final StreamController<int> _activeController =
      StreamController<int>.broadcast();
  StreamSubscription<Duration>? _sub;
  int _index = -1;
  Duration? _nextTransition;

  /// Active line index stream; emits `-1` before the first line.
  Stream<int> get activeLineStream => _activeController.stream;

  /// When the active line will change next (null after the last line).
  Duration? get nextTransition => _nextTransition;

  /// Current active index without subscribing (useful for initial paint).
  int get activeIndex => _index;

  void _onPosition(Duration position) {
    var index = -1;
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].startTime <= position) {
        index = i;
      } else {
        break;
      }
    }
    _nextTransition =
        index + 1 < _lines.length ? _lines[index + 1].startTime : null;
    if (index == _index) {
      return;
    }
    _index = index;
    if (!_activeController.isClosed) {
      _activeController.add(index);
    }
  }

  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    if (!_activeController.isClosed) {
      unawaited(_activeController.close());
    }
  }
}

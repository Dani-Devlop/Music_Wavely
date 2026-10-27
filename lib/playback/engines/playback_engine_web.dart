import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/engines/web_playback_engine.dart';

/// Web engine factory (selected by the conditional import in
/// engine_factory.dart when `dart.library.js_interop` is available).
PlaybackEngine createEngine() => WebPlaybackEngine();

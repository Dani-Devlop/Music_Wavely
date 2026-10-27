import 'package:wavely/playback/engines/playback_engine.dart';

/// Fallback engine factory for platforms with neither `dart:io` nor
/// `dart:js_interop` (never reached on the supported targets).
PlaybackEngine createEngine() =>
    throw UnsupportedError('Playback is not supported on this platform.');

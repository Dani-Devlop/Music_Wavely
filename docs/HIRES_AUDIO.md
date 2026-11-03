# Hi-Res Audio & Bit-Perfect Playback (Stage 4)

Status: **implemented (software side)**. This document is the contract for
the engine configuration, the Android platform channel stub, and the
owner actions needed for on-device exclusive mode.

## Principles

1. **Never resample by configuration.** Wavely never forces an output
   sample rate or bit depth anywhere in the chain:
   - media_kit/libmpv: `audio-samplerate` and `audio-format` are left at
     their defaults ("auto"), which passes the decoded stream to the
     device whenever the hardware supports it.
   - just_audio: no downmixing / rate conversion is configured; the
     Android `AudioSessionConfiguration.music()` profile only sets
     focus/ducking semantics, not rates.
2. **Opt-in exclusivity.** Exclusive (bit-perfect) output is a user
   setting, not a global default — exclusive mode grabs the audio device
   and silences other apps.
3. **Fail soft.** Every hi-res request degrades to "not granted" with a
   reason. Playback is never blocked by a hi-res failure.

## Desktop (Windows / macOS / Linux — media_kit/libmpv)

`DesktopPlaybackEngine.setExclusiveMode(bool)` writes the mpv property
`audio-exclusive=yes|no` via `NativePlayer.setProperty`:

| Platform | Exclusive mode backend |
| --- | --- |
| Windows | WASAPI exclusive |
| macOS | CoreAudio exclusive (hog mode) |
| Linux | ALSA exclusive |

In exclusive mode the OS mixer is bypassed: if the device and the file
agree (e.g. 24-bit/96 kHz FLAC on a 96 kHz-capable DAC), the samples reach
the hardware unresampled.

The equalizer (`audio af lavfi=[equalizer=...]`) and exclusive mode are
independent; mpv applies the filter chain before the output sink. Note
that enabling EQ means the signal is processed — for a true bit-perfect
chain, disable the EQ.

## Android (just_audio)

### What is implemented

- `HiResAudioPolicy.androidExclusiveSupported(sdkInt)` — pure gate:
  exclusive AAudio requests are only attempted on **Android 14+
  (API 34)**.
- `HiResAudioController.enableAndroidExclusiveMode()` — orchestrates the
  gate + channel call and returns a `HiResRequestResult(granted, reason)`.
- `app.wavely.hires.audio` platform channel (`requestExclusiveMode` →
  `bool`). The native handler is **not committed** (the repo scaffolds its
  Android runner in CI), so today the channel resolves through
  `MissingPluginException` → `granted: false`. This is the documented
  stub state.

### Owner action — native handler sketch

Add to the scaffolded `android/app/src/main/kotlin/.../MainActivity.kt`
(and commit the runner folder if desired):

```kotlin
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.audiofx.AcousticEchoCanceler // not required; see notes
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.wavely.hires.audio"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestExclusiveMode" -> {
                    // Expose the AAudio path through ExoPlayer/just_audio's
                    // AudioOffload or a custom AudioSink:
                    //   AudioAttributes.Builder()
                    //       .setUsage(USAGE_MEDIA)
                    //       .setContentType(CONTENT_TYPE_MUSIC)
                    //       .build()
                    // then request PERFORMANCE_MODE_EXCLUSIVE on the
                    // AAudioStream (API 34+: isAAudioExclusiveSupported).
                    // The just_audio side reports the outcome via the
                    // boolean below.
                    result.success(false) // replace with the real outcome
                }
                else -> result.notImplemented()
            }
        }
    }
}
```

Alternative without custom native code: `audio_session`'s
`AndroidAudioAttributes(usageType: AndroidUsageType.media)` keeps the
music profile; just_audio delegates to ExoPlayer whose `AudioSink`
already prefers `PERFORMANCE_MODE_EXCLUSIVE`-capable offload paths when
the format allows it. Verify with
`adb shell dumpsys media.audio_flinger` (look for the fast track flag).

## Verifying a bit-perfect chain (owner checklist)

1. Play a FLAC whose sample rate matches the DAC's current mode.
2. Desktop: `mpv --msg-level=ao=debug` equivalent — check
   `ao/wasapi` / `ao/alsa` logs for "exclusive" / no resample.
3. Android: `dumpsys media.audio_flinger` → the track should show the
   native sample rate (e.g. 96000 Hz) and, with exclusive mode granted, a
   fast-mixer path.

## Related code

- `lib/playback/hires/hires_audio.dart` — policy + controller + channel.
- `lib/playback/engines/desktop_playback_engine.dart` — `setExclusiveMode`.
- `test/playback/hires/hires_audio_test.dart` — policy/gate tests.

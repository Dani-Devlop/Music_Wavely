# DAP-Class Features (Stage 4)

Stage 4 turns Wavely into a digital-audio-player-class app: multi-arch
releases, Hi-Res/bit-perfect audio, a software equalizer with per-device
presets, and a sandboxed plugin architecture. This document is the
overview; platform contracts live in `docs/HIRES_AUDIO.md` and
`docs/PACKAGING.md`.

## 1. Multi-architecture release assets

`release.yml` produces, on every `v*.*.*` tag:

| Platform | Assets |
| --- | --- |
| Android | `wavely-<tag>-android-universal.apk` + 4 split APKs: `armeabi-v7a`, `arm64-v8a`, `x86`, `x86_64` (`--split-per-abi`) |
| Windows | x64 only: `wavely-<tag>-windows-x64.zip` + MSIX (signed iff `MSIX_CERTIFICATE` secret exists) |
| Linux | x64 only: `wavely-<tag>-linux-x64.tar.gz` + AppImage (`.sig` iff `APPIMAGE_SIGNING_KEY` exists) + `.flatpak` |

Every release also carries `SHA256SUMS.txt`.

## 2. Hi-Res audio & bit-perfect output

- Desktop: `DesktopPlaybackEngine.setExclusiveMode(bool)` → mpv
  `audio-exclusive` (WASAPI/CoreAudio/ALSA exclusive). No forced
  `audio-samplerate`/`audio-format` anywhere — the decoder's native rate
  passes through when the device supports it.
- Android: `HiResAudioController` gates on **Android 14+ (API 34)** and
  requests AAudio exclusive mode through the documented platform channel
  `app.wavely.hires.audio` (method `requestExclusiveMode`). The native
  handler is a documented stub (`granted: false` until the owner wires
  the Kotlin side) — see `docs/HIRES_AUDIO.md`.

## 3. Equalizer (per-device presets)

Architecture:

```
UI / controller API
        │
EqualizerController (lib/playback/equalizer/equalizer_controller.dart)
        │                                │
        │ opt-in capability check        │ presets
        ▼                                ▼
EqualizerControl (engine capability)   eq_presets (Drift, schema v5)
        │                                scoped by DeviceIdentity uuid
        ├── MobilePlaybackEngine (Android): just_audio AudioPipeline +
        │   AndroidEqualizer (device band count / range)
        └── DesktopPlaybackEngine (media_kit): 10-band synthetic EQ pushed
            to libmpv as lavfi=[equalizer=...] (eq_filter.dart)
```

Key properties:

- `PlaybackEngine` is untouched — engines opt into `EqualizerControl`,
  so fakes, contract tests and older engines keep compiling.
- Built-in presets (`kBuiltinEqPresets`: Flat, Bass Boost, Vocal Boost,
  Treble Boost, Rock, Electronic) are authored over the standard 10-band
  layout and resampled to the engine's real band count
  (`EqualizerGains.resample`).
- User presets persist in the Drift table `eq_presets` (schemaVersion 5,
  migration 0005), keyed by `(deviceId, name)` with a unique index.
  `deviceId` is a UUIDv4 created by `DeviceIdentity`
  (`lib/core/device/device_identity.dart`) on first run and stored via
  the app settings store — one id per installation, so a synced account
  can keep different curves per device.
- Gains are clamped to ±12 dB before they reach engines or storage; all
  engine calls are best-effort and non-throwing.

## 4. Plugin support (sandboxed by design)

- Contract: `lib/plugins/plugin_api.dart` (`WavelyPlugin`,
  `PluginManifest`, `PluginCapability`, `PluginHostContext`).
- Host: `lib/plugins/plugin_host.dart` — compile-time factories,
  per-plugin failure isolation, host-owned source registry.
- Proof implementation: `lib/plugins/bundled/local_folder_plugin.dart`
  ("Local Folders") — a read-only `SourceProvider` over user folders,
  built entirely on the injectable `FileSystem` seam (MemoryFileSystem in
  tests). It passes the same shared contract suite as the Stage 2.1
  online sources.

### Security model (no arbitrary code execution)

- Plugins are **compiled in** — there is no dynamic library loading, no
  code download/evaluation, no runtime introspection of arbitrary files.
- A plugin receives ONLY a `PluginHostContext` with one method
  (`registerSource`). No database, no credentials, no process access.
- Capabilities are declared in the manifest (`source`, future: `metadata`,
  `lyrics`) and enforced by the host; the host may ignore registrations.
- Every plugin failure is isolated: a throwing `init`/`dispose` affects
  only that plugin.
- Future extension path: *declarative* plugins — JSON manifests describing
  REST catalog endpoints — evaluated inside the existing rate-limited,
  cached HTTP layer, never as executable code.

## 5. Signed installers (conditional)

Signing is secret-driven and never build-breaking:

- `MSIX_CERTIFICATE` (+ optional `MSIX_CERTIFICATE_PASSWORD`) → signed
  MSIX; absent → unsigned MSIX.
- `APPIMAGE_SIGNING_KEY` → detached `.sig` next to the AppImage; absent →
  unsigned AppImage.

Owner instructions: `docs/PACKAGING.md` §8.

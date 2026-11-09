# Packaging & release (Stage 2.2)

Build commands per platform, packaging configs, the release workflow and
the owner actions that cannot be done from a sandbox.

## 1. Per-platform build commands

```bash
# Common prelude (every platform):
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# Android (arm64 release APK)
flutter build apk --release --target-platform android-arm64
# → build/app/outputs/flutter-apk/app-release.apk

# Windows (MSIX)
flutter config --enable-windows-desktop
flutter build windows --release
flutter pub add --dev msix
dart run msix:create          # reads msix_config.yaml (sign: false)
# → build/windows/x64/runner/Release/*.msix

# Linux (tarball + AppImage)
flutter config --enable-linux-desktop
flutter build linux --release
tar -czf wavely-linux-x64.tar.gz -C build/linux/x64/release .
dart pub global activate flutter_distributor 0.6.10
flutter_distributor package --platform=linux --targets=appimage --skip-tests
# → dist/*.AppImage

# Web / PWA / Telegram Mini App
flutter build web --dart-define=TELEGRAM_MODE=true
# → build/web (manifest.json + service_worker.js included)
```

## 2. Release workflow

`.github/workflows/release.yml` triggers on **tag push `v*.*.*`** (plus a
manual `workflow_dispatch`):

- `build-android` → arm64 APK artifact
- `build-windows` → zip bundle + **unsigned** MSIX (`continue-on-error`:
  tooling drift fails soft, the zip remains)
- `build-linux` → tarball + AppImage attempt (`continue-on-error` —
  linuxdeploy/appimagetool are downloaded by the distributor at run time)
- `release` → `gh release create` attaching everything

Android signs with the committed shared keystore (§3 below); MSIX /
AppImage signing secrets are optional owner configuration.

## 3. Signing (owner actions)

### Android (sideload updates install cleanly — FIXED)

**Root cause of the recurring "App not installed as package conflicts with
an existing package" error:** the repo does not commit `android/`; the
runner is scaffolded by `flutter create . --platforms=android` in CI and
the template signed release builds with the DEBUG keystore. Ephemeral CI
runners regenerate `~/.android/debug.keystore` on every run, so every
release APK carried a different signature → Android refused to update the
installed app.

**Fix (owner decision):** a shared release keystore is committed —
`android/signing/wavely-release.jks` + `android/signing/key.properties`
(deliberate exception to the `*.jks` ignore rule). CI wires it in via
`tools/patch_android_signing.py` (run after `flutter create`, before
`flutter pub get`); the patch is idempotent, supports both the Kotlin and
Groovy gradle DSLs, and falls back to debug signing when the signing
folder is absent (forks still build).

Consequences:

- Every APK — local build or CI release — now shares ONE signature, so
  updates install over existing installs without uninstalling.
- Keystore credentials (public repo): alias `wavely`, password
  `wavely2025`. Acceptable for a sideload-only open-source app; anyone
  can build an APK signed "as Wavely".
- **One-time migration:** the app currently installed on your device was
  signed with an older ephemeral key. Uninstall it ONCE, install the next
  build, and every update after that installs cleanly.
- To rotate to a private keystore later (e.g. before Play Store): remove
  `android/signing/`, generate a local keystore
  (`keytool -genkeypair -v -keystore wavely-release.jks -alias wavely
  -keyalg RSA -keysize 2048 -validity 10950`), and pass it through CI
  secrets instead (`ANDROID_KEYSTORE_BASE64` → decode to
  `android/signing/wavely-release.jks`, keep the same key.properties
  format). Remember: rotating the key means users must uninstall once
  more.

### Windows / MSIX

1. Obtain a code-signing certificate (EV preferred for SmartScreen).
2. Edit `msix_config.yaml`:
   ```yaml
   publisher: CN=<YOUR CERT SUBJECT>     # must match the cert exactly
   certificate_path: path/to/cert.pfx    # local only — NEVER commit
   certificate_password: <secret>        # local only — NEVER commit
   sign: true
   ```
3. `dart run msix:create` locally; the CI artifact stays unsigned by
   design (`sign: false` committed).

### Linux / AppImage

- AppImages are distributed unsigned; optionally sign with
  `appimagetool --sign`.

### macOS (future)

- `.dmg` artifacts are picked by the updater asset matcher, but no
  packaging pipeline ships yet — needs the owner's Apple Developer
  account and notarization.

## 4. Icons (owner actions)

- `web/icons/icon-{48..512}.png` are **generated placeholders**
  (`#7C5CFF` background + white waveform). Replace with real brand assets
  at the same sizes before release.
- `windows/runner/resources/app_icon.ico` and the platform asset
  catalogs remain Flutter defaults — replace alongside the MSIX build.
- `msix_config.yaml` `logo_path` points at the placeholder ico.

## 5. Auto-update

`lib/features/settings/data/update_service.dart`:

- `checkForUpdate()` → GitHub Releases API
  (`Dani-Devlop/Music_Wavely/releases/latest`), numeric-aware version
  compare, platform asset pick (`.msix` / `.AppImage` / `.apk` / `.dmg`).
- The Settings "Check for updates" row surfaces the result as a SnackBar
  and opens the release page through the existing `LinkLauncher`.
- `auto_updater ^1.0.0` (Sparkle/WinSparkle wrapper) is wired as a
  dependency for a future in-place install flow; the current install path
  stays user-visible (download from the release page) until the owner
  provides signing + feed URLs.
- To ship a release: tag `vX.Y.Z` on `main` and push the tag.

```bash
git tag v0.1.0
git push origin v0.1.0
```

## 6. Flatpak

- Manifest: `flatpak/app.wavely.music.yml` (`app-id app.wavely.music`,
  Freedesktop 23.08 runtime, network + pulseaudio + home filesystem).
- Desktop entry: `flatpak/app.wavely.music.desktop`.
- Local build (after a Linux bundle exists):
  ```bash
  flatpak-builder --force-clean build-dir flatpak/app.wavely.music.yml
  ```

## 7. Checklist before the first real release

- [ ] Replace placeholder PWA icons (§4)
- [ ] Replace Windows ico; set MSIX publisher/cert (§3)
- [ ] Create the GitHub release tag
- [ ] Verify the update checker sees the new release (Settings row)
- [ ] Confirm `docs/PRIVACY.md` claims match the shipped build (crash-only
      Sentry opt-in, no analytics)

## 8. Stage 4 — conditional CI signing (secrets-based)

The release workflow now signs installers **when the corresponding GitHub
secrets are configured**; with no secrets present it emits honest
"unsigned" artifacts and the build NEVER fails because of signing.

### MSIX (Windows)

| Secret | Content |
| --- | --- |
| `MSIX_CERTIFICATE` | The PFX certificate, **base64-encoded** |
| `MSIX_CERTIFICATE_PASSWORD` | The PFX password (may be empty) |

Encoding an existing PFX (Linux/macOS):
`base64 -w0 mycert.pfx` (macOS: `base64 -i mycert.pfx`).

With the secret present the workflow decodes it to `signing.pfx` and runs
`dart run msix:create --certificate-path signing.pfx
--certificate-password <secret> --install-certificate false`
(the certificate is never installed on the runner). Without the secret
the step logs `building an UNSIGNED MSIX` and runs the plain
`dart run msix:create` from `msix_config.yaml` (`sign: false`).

### AppImage (Linux)

| Secret | Content |
| --- | --- |
| `APPIMAGE_SIGNING_KEY` | Armored GPG private key (`-----BEGIN PGP PRIVATE KEY BLOCK-----`) |

With the secret present the workflow imports the key and produces a
**detached signature** next to the bundle (`wavely-<tag>-linux-x64.AppImage.sig`)
via `gpg --detach-sign`. Verify after download:

```bash
gpg --import owner-public.asc
gpg --verify wavely-<tag>-linux-x64.AppImage.sig wavely-<tag>-linux-x64.AppImage
```

Without the secret the step logs `AppImage stays UNSIGNED` and exits 0.

### Integrity baseline (always)

Every release ships `SHA256SUMS.txt` covering all assets regardless of
signing state.

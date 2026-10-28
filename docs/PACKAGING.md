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

**No signing secrets live in the workflow.** Artifacts are honest
placeholders until the owner signs them.

## 3. Signing (owner actions)

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

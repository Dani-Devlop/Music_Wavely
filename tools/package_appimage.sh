#!/usr/bin/env bash
# Packages the Flutter Linux bundle into a self-contained .AppImage.
#
# WHY NOT flutter_distributor?
#   0.6.10 (the latest upstream release) hard-fails for this app: its
#   appimage maker runs `ldd -d` over every bundled .so and throws when a
#   prebuilt ffmpeg_kit library references a soname the CI runner no longer
#   ships (libvpx.so.7, libx265.so.199, libtheora{enc,dec}.so.1,
#   libopencore-amrnb.so.0, libvo-amrwbenc.so.0, libxml2.so.2). Its parser
#   even turns the `=> not found` output into a literal `cp not ...`
#   command ("MakeError: cp: cannot stat 'not'"). There is no exclude
#   option and no newer version to upgrade to, so this script re-implements
#   the maker's dependency collection with tolerance:
#
#     1. Assemble the AppDir from build/linux/x64/release/bundle.
#     2. Ship the MISSING sonames alongside the bundle ("compat set" —
#        pinned Ubuntu 22.04 (jammy) debs, the distro family the
#        ffmpeg_kit prebuilts were built on), so the AppImage is
#        self-contained for them.
#     3. Copy the runner-resolved shared libraries every bundled .so needs
#        (skipping the glibc core, which must come from the host, and the
#        libflutter_linux_gtk.so dependency set — GTK comes from the host,
#        bundling it breaks theming).
#     4. Pack with the official appimagetool (APPIMAGE_EXTRACT_AND_RUN=1 —
#        runners have no FUSE).
#
# Usage: package_appimage.sh <bundle-dir> <output-AppImage-path>
set -euo pipefail

BUNDLE="${1:?usage: package_appimage.sh <bundle-dir> <output-AppImage-path>}"
OUTPUT="${2:?usage: package_appimage.sh <bundle-dir> <output-AppImage-path>}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPIMAGE_TEMPLATES="$REPO_ROOT/linux/packaging/appimage"
APPDIR="$(pwd)/wavely.AppDir"
COMPAT_DIR="$(pwd)/.appimage-compat"
TOOL_DIR="$(pwd)/.appimage-tools"

rm -rf "$APPDIR" "$COMPAT_DIR" "$TOOL_DIR"
mkdir -p "$APPDIR/usr" "$APPDIR/usr/share/applications" \
  "$APPDIR/usr/share/icons/hicolor/512x512/apps" \
  "$COMPAT_DIR" "$TOOL_DIR"

# ── 1. Payload: binary + lib/ + data/ keep the upstream bundle layout ────
cp -a "$BUNDLE/." "$APPDIR/usr/"

# ── 2. Launcher, desktop entry, icons ─────────────────────────────────────
install -m 0755 "$APPIMAGE_TEMPLATES/AppRun" "$APPDIR/AppRun"
install -m 0644 "$APPIMAGE_TEMPLATES/wavely.desktop" "$APPDIR/wavely.desktop"
install -m 0644 "$APPIMAGE_TEMPLATES/wavely.desktop" \
  "$APPDIR/usr/share/applications/wavely.desktop"
install -m 0644 "$REPO_ROOT/web/icons/icon-512.png" "$APPDIR/wavely.png"
install -m 0644 "$REPO_ROOT/web/icons/icon-512.png" \
  "$APPDIR/usr/share/icons/hicolor/512x512/apps/wavely.png"
ln -sf wavely.png "$APPDIR/.DirIcon"

# ── 3. Compat set: sonames the bundle needs but modern runners lack ──────
# Pinned jammy (22.04) debs — the ffmpeg_kit prebuilts were linked against
# this soname generation. Extracted into AppDir/usr/lib, where the bundle's
# RPATH/AppRun LD_LIBRARY_PATH resolve them. https for integrity.
COMPAT_DEBS=(
  "https://archive.ubuntu.com/ubuntu/pool/main/libv/libvpx/libvpx7_1.11.0-2ubuntu2_amd64.deb"
  "https://archive.ubuntu.com/ubuntu/pool/main/libt/libtheora/libtheora0_1.1.1+dfsg.1-15ubuntu2_amd64.deb"
  "https://archive.ubuntu.com/ubuntu/pool/main/libx/libxml2/libxml2_2.9.13+dfsg-1ubuntu0.14_amd64.deb"
  "https://archive.ubuntu.com/ubuntu/pool/main/i/icu/libicu70_70.1-2ubuntu1_amd64.deb"
  "https://archive.ubuntu.com/ubuntu/pool/main/libo/libogg/libogg0_1.3.5-0ubuntu3_amd64.deb"
  "https://archive.ubuntu.com/ubuntu/pool/main/n/numactl/libnuma1_2.0.14-3ubuntu2_amd64.deb"
  "https://archive.ubuntu.com/ubuntu/pool/universe/o/opencore-amr/libopencore-amrnb0_0.1.6-1build2_amd64.deb"
  "https://archive.ubuntu.com/ubuntu/pool/universe/o/opencore-amr/libopencore-amrwb0_0.1.6-1build2_amd64.deb"
  "https://archive.ubuntu.com/ubuntu/pool/universe/v/vo-amrwbenc/libvo-amrwbenc0_0.1.3-2build2_amd64.deb"
  "https://archive.ubuntu.com/ubuntu/pool/universe/x/x265/libx265-199_3.5-2build1_amd64.deb"
)
for deb_url in "${COMPAT_DEBS[@]}"; do
  deb_file="$COMPAT_DIR/$(basename "$deb_url")"
  echo "compat: fetching $(basename "$deb_url")"
  curl -sSfL -o "$deb_file" "$deb_url"
  dpkg-deb -x "$deb_file" "$COMPAT_DIR/extract"
done
find "$COMPAT_DIR/extract" -type f -name '*.so*' -exec cp -a {} "$APPDIR/usr/lib/" \;

# ── 4. Runner-resolved dependencies of every bundled .so ─────────────────
# Same pass the distributor maker did, minus the fatal part: `not found`
# entries are EXPECTED here (covered by the compat set) and are skipped
# instead of crashing the build. The glibc core is never bundled (it must
# come from the host); libflutter_linux_gtk.so's own dependency set is the
# GTK stack, which also stays on the host (bundling GTK breaks theming).
copy_resolved_deps() {
  local so="$1" line lib base
  while IFS= read -r line; do
    case "$line" in
      *"not found"*) continue ;;
      *" => "*) ;;
      *) continue ;;
    esac
    lib="${line#* => }"
    lib="${lib%% (*}"
    lib="${lib%%[[:space:]]*}"
    base="$(basename "$lib")"
    case "$base" in
      libc.so* | libm.so* | libdl.so* | libpthread.so* | librt.so* | \
        ld-linux* | libresolv.so* | libnss_* | libutil.so* | libanl.so* | \
        libmvec.so* | libBrokenLocale.so* | libcrypt.so*)
        continue
        ;;
    esac
    # Skip anything already staged (bundle libs, compat set, prior copies).
    [ -e "$APPDIR/usr/lib/$base" ] && continue
    # Skip paths that already live inside the payload.
    case "$lib" in "$APPDIR"/* | "$BUNDLE"/*) continue ;; esac
    if [ -f "$lib" ]; then
      cp -L "$lib" "$APPDIR/usr/lib/$base"
    fi
  done < <(ldd "$so" 2>/dev/null || true)
}

find "$APPDIR/usr/lib" -maxdepth 1 -type f -name '*.so*' ! -name 'libflutter_linux_gtk.so' |
  while IFS= read -r so; do
    copy_resolved_deps "$so"
  done

echo "appimage: staged $(ls "$APPDIR/usr/lib" | wc -l) libraries in usr/lib"

# ── 5. Pack with the official appimagetool ────────────────────────────────
# No FUSE on runners: APPIMAGE_EXTRACT_AND_RUN=1 makes the nested AppImage
# extract-and-run. mksquashfs comes from the distro (squashfs-tools).
APPIMAGETOOL="$TOOL_DIR/appimagetool-x86_64.AppImage"
curl -sSfL -o "$APPIMAGETOOL" \
  "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
chmod +x "$APPIMAGETOOL"

mkdir -p "$(dirname "$OUTPUT")"
APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGETOOL" --no-appstream \
  "$APPDIR" "$OUTPUT"

test -s "$OUTPUT" || { echo "appimage: output missing/empty" >&2; exit 1; }

# Remove transient state — the tool dir holds appimagetool, whose file
# name matches *.AppImage and would otherwise be swept up by the CI
# staging pass (find -name '*.AppImage') and uploaded as a release asset.
rm -rf "$APPDIR" "$COMPAT_DIR" "$TOOL_DIR"

echo "appimage: built $(basename "$OUTPUT") ($(du -h "$OUTPUT" | cut -f1))"

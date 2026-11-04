#!/usr/bin/env python3
"""Generate a WinSparkle appcast.xml from the staged release artifacts.

WinSparkle (the Windows side of the `auto_updater` package) consumes a
Sparkle-style RSS appcast. The release job runs this script over `dist/`
and uploads the result as a release asset, so the in-app updater can
always resolve:

    https://github.com/Dani-Devlop/Music_Wavely/releases/latest/download/appcast.xml

The enclosure is the MSIX build; `sparkle:version` carries the 4-part
Windows file version Flutter stamps into the runner (pubspec `1.0.1+5`
-> `1.0.1.5`) and `sparkle:shortVersionString` the human `1.0.1`.

Usage:

    python3 tools/generate_appcast.py <dist-dir> <tag-name>

Exits non-zero when the inputs are missing (the release job treats that
as best-effort: the in-app updater falls back to downloading the MSIX).
"""

from __future__ import annotations

import email.utils
import re
import sys
from pathlib import Path

REPO = "Dani-Devlop/Music_Wavely"
PUBSPEC = Path("pubspec.yaml")


def app_version() -> tuple[str, str]:
    """Returns (short, full) — e.g. ('1.0.1', '1.0.1.5') from pubspec."""
    text = PUBSPEC.read_text(encoding="utf-8")
    match = re.search(r"^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)", text, re.M)
    if not match:
        raise SystemExit("pubspec.yaml: could not parse `version:`")
    major, minor, patch, build = match.groups()
    short = f"{major}.{minor}.{patch}"
    return short, f"{short}.{build}"


def main() -> int:
    dist = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("dist")
    tag = sys.argv[2] if len(sys.argv) > 2 else ""
    if not tag.startswith("v"):
        print("[appcast] ERROR: tag argument required (e.g. v1.0.1)")
        return 1
    if not dist.is_dir():
        print(f"[appcast] ERROR: {dist} does not exist")
        return 1
    msix_files = sorted(dist.glob("*.msix"))
    if not msix_files:
        print(f"[appcast] ERROR: no .msix staged in {dist}")
        return 1
    msix = msix_files[0]

    short, full = app_version()
    base = f"https://github.com/{REPO}/releases/download/{tag}"
    notes = f"https://github.com/{REPO}/releases/tag/{tag}"
    pub_date = email.utils.formatdate(usegmt=True)

    xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Wavely</title>
    <link>https://github.com/{REPO}</link>
    <description>Wavely for Windows — release feed</description>
    <language>en</language>
    <item>
      <title>Wavely {short}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:releaseNotesLink>{notes}</sparkle:releaseNotesLink>
      <enclosure
          url="{base}/{msix.name}"
          sparkle:version="{full}"
          sparkle:shortVersionString="{short}"
          type="application/vnd.msixpackage"
          length="{msix.stat().st_size}"/>
    </item>
  </channel>
</rss>
"""
    (dist / "appcast.xml").write_text(xml, encoding="utf-8")
    print(f"[appcast] wrote {dist / 'appcast.xml'} -> {msix.name} ({full})")
    return 0


if __name__ == "__main__":
    sys.exit(main())

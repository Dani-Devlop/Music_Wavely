#!/usr/bin/env python3
"""Patch the scaffolded Android runner for Android 13+ per-app language.

Phase 11 (Localization: Persian & RTL first-class): declares the
`localeConfig` resource plus the three shipped locales so Android 13+ shows
Wavely in the system "App languages" settings (Settings → Apps → Wavely →
Languages). The Flutter engine resolves `Locale('fa')` automatically from
that selection because the MaterialApp supports it.

Also enables `resourceConfigurations` for en+fa in the Gradle build so the
APKs ship the localized AndroidX/Material strings for both languages.

Run after scaffolding (release.yml does the same in CI):

    python3 tools/patch_android_per_app_language.py

Idempotent: running it twice changes nothing. Exits 0 with a note when no
Android runner is present.
"""

from __future__ import annotations

import sys
from pathlib import Path

APP_DIR = Path("android") / "app"
MAIN_SRC = APP_DIR / "src" / "main"

MANIFEST = MAIN_SRC / "AndroidManifest.xml"

LOCALE_CONFIG_XML = """<?xml version="1.0" encoding="utf-8"?>
<!-- Phase 11: Android 13+ per-app language (tools/patch_android_per_app_language.py) -->
<locale-config xmlns:android="http://schemas.android.com/apk/res/android">
    <locale android:name="en" />
    <locale android:name="fa" />
</locale-config>
"""

MANIFEST_SNIPPET = """        <!-- Phase 11: per-app language (Android 13+) -->
        <service
            android:name="android.app.AppLocalesMetadataHolderService"
            android:enabled="false"
            android:exported="false">
            <meta-data
                android:name="android.app.app_locale_config"
                android:resource="@xml/locales_config" />
        </service>
"""


def patch_locales_config() -> bool:
    xml_dir = MAIN_SRC / "res" / "xml"
    xml_dir.mkdir(parents=True, exist_ok=True)
    target = xml_dir / "locales_config.xml"
    if target.exists():
        print(f"[patch] {target}: already present")
    else:
        target.write_text(LOCALE_CONFIG_XML, encoding="utf-8")
        print(f"[patch] {target}: wrote locale-config resource")
    return True


def patch_manifest() -> bool:
    if not MANIFEST.exists():
        print(f"[patch] ERROR: {MANIFEST} missing")
        return False
    src = MANIFEST.read_text(encoding="utf-8")
    if "AppLocalesMetadataHolderService" in src:
        print(f"[patch] {MANIFEST}: per-app language already declared")
        return True
    needle = "</application>"
    index = src.find(needle)
    if index < 0:
        print(f"[patch] ERROR: no </application> tag found in {MANIFEST}")
        return False
    src = src[:index] + MANIFEST_SNIPPET + src[index:]
    MANIFEST.write_text(src, encoding="utf-8")
    print(f"[patch] {MANIFEST}: declared localeConfig (Android 13+)")
    return True


def patch_gradle_resource_config() -> bool:
    """Ships en+fa localized strings in release APKs."""
    for name in ("build.gradle.kts", "build.gradle"):
        build_file = APP_DIR / name
        if not build_file.exists():
            continue
        src = build_file.read_text(encoding="utf-8")
        if "resourceConfigurations" in src:
            print(f"[patch] {build_file}: resourceConfigurations already set")
            return True
        marker = 'defaultConfig {'
        index = src.find(marker)
        if index < 0:
            continue
        insertion = (
            "defaultConfig {\n"
            "        // Phase 11: ship only the localized platform strings we support.\n"
            "        resourceConfigurations += listOf(\"en\", \"fa\")"
        )
        src = src.replace(marker, insertion, 1)
        build_file.write_text(src, encoding="utf-8")
        print(f"[patch] {build_file}: resourceConfigurations += en, fa")
        return True
    print("[patch] no Gradle build file found — skipping resourceConfigurations")
    return True


def main() -> int:
    if not APP_DIR.exists():
        print(
            "[patch] no Android runner found (android/app missing) — "
            "scaffold it first with `flutter create . --platforms=android`"
        )
        return 0
    if not patch_locales_config():
        return 1
    if not patch_manifest():
        return 1
    if not patch_gradle_resource_config():
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

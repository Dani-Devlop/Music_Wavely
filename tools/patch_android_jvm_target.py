#!/usr/bin/env python3
"""Raise the jvmTarget of Kotlin plugins that pin JVM 1.8 in the pub cache.

`home_widget` (0.8.x/0.10.x) ships `android/build.gradle` with
`kotlinOptions.jvmTarget = "1.8"` while its androidx dependencies expose
inline functions compiled with JVM target 11. The Kotlin compiler's
inliner refuses to inline newer-target bytecode into a 1.8 compilation:

    Cannot inline bytecode built with JVM target 11 into bytecode that is
    being built with JVM target 1.8. Specify proper '-jvm-target' option.

Note this is a *compiler* check, not the KGP jvm-target validation —
`kotlin.jvm.target.validation.mode=warning` does NOT cover it. The
plugin module must itself compile with jvmTarget >= 11.

The plugin's build.gradle lives in the pub cache (not committed), so this
script rewrites it in place. Run AFTER `flutter pub get` (release.yml and
e2e.yml do the same in CI). Idempotent: running it twice changes nothing.

    python3 tools/patch_android_jvm_target.py
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

# Plugins whose Kotlin module pins jvmTarget 1.8 and trips the compiler's
# inline-target check. Extend as needed.
TARGET_PLUGINS = {
    "home_widget": "11",
}

OLD_TARGETS = {"1.8", "1.7", "1.6"}


def patch_plugin(plugin_dir: Path, target: str) -> bool:
    """Raise jvmTarget in a plugin's android build files. True if changed."""
    changed = False
    for name in ("build.gradle", "build.gradle.kts"):
        path = plugin_dir / "android" / name
        if not path.exists():
            continue
        src = path.read_text(encoding="utf-8")

        pattern = re.compile(
            r"(jvmTarget\s*[=:]\s*)(?:\"|')?(" + "|".join(map(re.escape, OLD_TARGETS)) + r")(?:\"|')?"
        )
        updated, n = pattern.subn(rf"\g<1>{target}", src)
        if n:
            path.write_text(updated, encoding="utf-8")
            print(f"[patch] {path}: jvmTarget -> {target} ({n} occurrence(s))")
            changed = True
        else:
            print(f"[patch] {path}: jvmTarget already {target}+ (no 1.x pins)")
    return changed


def main() -> int:
    cache_root = Path(
        os.environ.get("PUB_CACHE") or (Path.home() / ".pub-cache")
    ) / "hosted" / "pub.dev"

    if not cache_root.exists():
        print(f"[patch] pub cache not found at {cache_root} — nothing to do")
        return 0

    patched_any = False
    for plugin, target in TARGET_PLUGINS.items():
        for plugin_dir in sorted(cache_root.glob(f"{plugin}-*")):
            if patch_plugin(plugin_dir, target):
                patched_any = True

    if not patched_any:
        print("[patch] no matching plugin pins found (already patched or absent)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

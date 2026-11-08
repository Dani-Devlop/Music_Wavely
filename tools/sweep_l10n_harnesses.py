#!/usr/bin/env python3
"""Phase 11 sweep: wire localizationsDelegates + supportedLocales into every
test-harness MaterialApp that lacks them, and add the AppLocalizations import
at the alphabetically-correct position."""
import re
import sys
from pathlib import Path

REPO = Path("/home/z/wavely")
NEW_IMPORT = "import 'package:wavely/l10n/app_localizations.dart';"
DELEGATES = "localizationsDelegates: AppLocalizations.localizationsDelegates,"
LOCALES = "supportedLocales: AppLocalizations.supportedLocales,"


def split_top_level(args: str):
    """Split an argument list on top-level commas (ignoring nested parens/brackets)."""
    parts, depth, cur = [], 0, ""
    for ch in args:
        if ch in "(<[{":
            depth += 1
        elif ch in ")]}>":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    return parts


files = sorted(REPO.glob("test/**/*.dart"))
changed = []
for f in files:
    text = f.read_text()
    if "MaterialApp(" not in text:
        continue
    if "localizationsDelegates" in text:
        continue  # already wired (the 5 harnesses + l10n_test)

    lines = text.split("\n")
    out = []
    i = 0
    patched = False
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if stripped.startswith("//"):
            out.append(line)
            i += 1
            continue
        if "MaterialApp(" in line:
            indent = line[: len(line) - len(line.lstrip())]
            inner_indent = indent + "  "
            # count parens to see if the MaterialApp arg list closes on this line
            opens = line.count("(") - line.count(")")
            if opens <= 0 and stripped.rstrip().endswith("),"):
                # single-line form: expand it
                start = line.index("MaterialApp(")
                # find the last ')' of the MaterialApp call
                last_close = line.rindex(")")
                args = line[start + len("MaterialApp(") : last_close]
                after = line[last_close + 1 :]  # usually ','
                out.append(f"{indent}{line[start:line.index('(', start)]}(")
                out.append(f"{inner_indent}{DELEGATES}")
                out.append(f"{inner_indent}{LOCALES}")
                # re-flow existing args (split top-level commas)
                args = args.strip().rstrip(",")
                parts = split_top_level(args)
                for p in parts:
                    out.append(f"{inner_indent}{p.strip()},")
                out.append(f"{indent}){after}")
            else:
                out.append(line)
                out.append(f"{inner_indent}{DELEGATES}")
                out.append(f"{inner_indent}{LOCALES}")
            patched = True
        else:
            out.append(line)
        i += 1

    if not patched:
        continue

    new_text = "\n".join(out)
    # insert the import in alphabetical position among package: imports
    imp_lines = [j for j, l in enumerate(new_text.split("\n")) if re.match(r"^import\s+'package:", l)]
    body = new_text.split("\n")
    if NEW_IMPORT in new_text:
        pass
    elif imp_lines:
        pos = None
        for j in imp_lines:
            m = re.search(r"'(package:[^']+)'", body[j])
            path = m.group(1)
            if path > "package:wavely/l10n/app_localizations.dart":
                pos = j
                break
        if pos is None:
            pos = imp_lines[-1] + 1
        body.insert(pos, NEW_IMPORT)
    else:
        # no package imports: insert after last import or after header
        last_import = max((j for j, l in enumerate(body) if l.startswith("import ")), default=-1)
        body.insert(last_import + 1, NEW_IMPORT)
    new_text = "\n".join(body)
    f.write_text(new_text)
    changed.append(f.relative_to(REPO))

print(f"patched {len(changed)} files:")
for c in changed:
    print(" ", c)

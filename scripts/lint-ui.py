#!/usr/bin/env python3
# Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
"""Nabız UI token linter: flags SwiftUI code that bypasses the design tokens.

usage: python3 lint.py <dir-or-file>... [--l10n] [--quiet]

  --l10n   also flag literal Text("...") that is not wrapped in L("tr", "en") or Text(verbatim:)
  --quiet  print only the per-rule totals

A line carrying `// nabiz-ui: ignore` (optionally followed by a reason) is skipped. Theme.swift and anything under DesignSystem/ is the token source
and is not checked. Exit code 1 when anything is found, so it can gate a commit.
"""
import re
import sys
from pathlib import Path

RULES = [
    ("raw-font", re.compile(r"\.system\(size:\s*\d"), "use Theme.title / body / bodyStrong / small / smallStrong"),
    ("raw-color", re.compile(r"(?<![\w.])(Color\.(red|orange|green|blue|yellow|purple|pink|gray)\b|\.foregroundStyle\(\.(red|orange|green|blue|yellow)\)|Color\(red:)"),
     "use Theme.accent / text / textMuted / danger / warning.mark|fill / Palette.green.mark"),
    ("raw-padding", re.compile(r"\.padding\((\.\w+,\s*)?([1-9]\d*(\.\d+)?)\)"), "use Theme.Spacing.xs/s/m/l/xl/xxl or the menu grid insets"),
    ("raw-radius", re.compile(r"cornerRadius:\s*[1-9]\d*"), "use Theme.radius (10) or Theme.fieldRadius (6)"),
    ("raw-spacing", re.compile(r"[HV]Stack\([^)]*spacing:\s*[1-9]\d*"), "use Theme.Spacing.*"),
    ("opaque-bg", re.compile(r"\.background\((Color\.(black|white)|Color\(nsColor:\s*\.windowBackgroundColor\))"),
     "follow the panelStyle setting: .appearanceRoot() / MenuMaterial, never a hard-coded opaque fill"),
    ("two-line-row", re.compile(r"\.lineLimit\([2-9]\)"), "panel rows are one line; put the rest in .help(...)"),
]
L10N = ("no-l10n", re.compile(r'Text\("(?!\\\()[^"]*[A-Za-z]'), 'wrap user-facing text in L("tr", "en") or use Text(verbatim:)')


def files(paths):
    for raw in paths:
        p = Path(raw)
        items = [p] if p.is_file() else sorted(p.rglob("*.swift"))
        for f in items:
            if f.name == "Theme.swift" or "DesignSystem" in f.parts or ".build" in f.parts:
                continue
            yield f


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    rules = RULES + ([L10N] if "--l10n" in sys.argv else [])
    quiet = "--quiet" in sys.argv
    if not args:
        print(__doc__)
        return 2
    totals = {name: 0 for name, _, _ in rules}
    for f in files(args):
        for number, line in enumerate(f.read_text(errors="ignore").splitlines(), 1):
            if "// nabiz-ui: ignore" in line or line.lstrip().startswith("//"):
                continue
            for name, pattern, hint in rules:
                if pattern.search(line):
                    totals[name] += 1
                    if not quiet:
                        print(f"{f}:{number}: [{name}] {line.strip()[:110]}\n    → {hint}")
    found = sum(totals.values())
    print("\n" + "  ".join(f"{k}: {v}" for k, v in totals.items()) + f"  — total {found}")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())

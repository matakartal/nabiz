#!/usr/bin/env python3
# Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
"""Checks a change against the repository's rules, looking only at the lines it adds.

usage: python3 scripts/pr-check.py [base-ref]      (default: origin/main)

- every Swift / Python source file the change touches starts with the copyright header;
- added Swift lines follow docs/DESIGN.md (the rules in scripts/lint-ui.py), wrap user-facing text in L("tr", "en"),
  and use no `try!`;
- no file over 1 MB is added (pictures for the README excepted), and no secrets-looking files.

Prints GitHub annotations when run in Actions, plain lines otherwise. Exit code 1 when anything is found.
"""
import importlib.util
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HEADER = "Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE."
IN_ACTIONS = os.environ.get("GITHUB_ACTIONS") == "true"

spec = importlib.util.spec_from_file_location("lint_ui", ROOT / "scripts" / "lint-ui.py")
lint_ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lint_ui)
RULES = lint_ui.RULES + [lint_ui.L10N, ("try-bang", re.compile(r"\btry!"), "handle the error; a broken answer shows a message, never a crash")]

problems = 0


def report(path, line, message):
    global problems
    problems += 1
    if IN_ACTIONS:
        print(f"::error file={path},line={line}::{message}")
    else:
        print(f"{path}:{line}: {message}")


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=True).stdout


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else "origin/main"
    merge_base = git("merge-base", base, "HEAD").strip()
    changed = [line.split("\t") for line in git("diff", "--name-status", "--diff-filter=AMR", merge_base).splitlines()]
    files = [parts[-1] for parts in changed]

    for name in files:
        path = ROOT / name
        if not path.is_file():
            continue
        if re.search(r"(\.env|\.p8|\.p12|\.pem|\.key|credentials?\.json)$", name, re.I):
            report(name, 1, "looks like a secret or credentials file; don't commit it")
        if path.stat().st_size > 1 << 20 and not name.startswith("docs/"):
            report(name, 1, "file over 1 MB; keep big assets out of the repository")
        if path.suffix in (".swift", ".py") and (name.startswith("Sources/") or name.startswith("Tests/") or name.startswith("scripts/")):
            head = path.read_text(errors="ignore").splitlines()[:3]
            if not any(HEADER in line for line in head):
                report(name, 1, f"start the file with the copyright header: // {HEADER}")

    # Only the lines this change adds, so older code doesn't block a contribution.
    diff = git("diff", "-U0", merge_base, "--", "*.swift")
    current, number = None, 0
    for line in diff.splitlines():
        if line.startswith("+++ "):
            current = line[6:] if line.startswith("+++ b/") else None
            continue
        hunk = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)", line)
        if hunk:
            number = int(hunk.group(1))
            continue
        if current is None or not line.startswith("+") or line.startswith("+++"):
            continue
        text = line[1:]
        skip = "Theme.swift" in current or "/DesignSystem/" in current or current.startswith("Tests/")
        if not skip and "nabiz-ui: ignore" not in text and not text.lstrip().startswith("//"):
            for rule, pattern, hint in RULES:
                if pattern.search(text):
                    report(current, number, f"[{rule}] {hint}")
        number += 1

    print(f"pr-check: {problems} problem(s) in {len(files)} changed file(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

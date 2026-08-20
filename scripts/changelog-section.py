#!/usr/bin/env python3
"""Print one version's section of CHANGELOG.md.

    scripts/changelog-section.py v0.1.0

Used by the release workflow to turn a tag into release notes. Exiting non-zero
on a missing section is deliberate: a tag with no changelog entry is a mistake
worth stopping the release for, not something to paper over with an empty body.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHANGELOG = ROOT / "CHANGELOG.md"


def section(version: str) -> str:
    version = version.lstrip("v")
    text = CHANGELOG.read_text()

    # Capture everything between this version's heading and the next one, or
    # the link definitions at the bottom of the file.
    pattern = re.compile(
        rf"^## \[{re.escape(version)}\][^\n]*\n(.*?)(?=^## \[|^\[[^\]]+\]:)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(text)
    if not match:
        available = re.findall(r"^## \[([^\]]+)\]", text, re.MULTILINE)
        sys.exit(
            f"error: no section for {version} in CHANGELOG.md\n"
            f"  found: {', '.join(available) or 'nothing'}"
        )

    body = match.group(1).strip()
    if not body:
        sys.exit(f"error: the section for {version} in CHANGELOG.md is empty")
    return body


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit("usage: changelog-section.py <version>")
    print(section(sys.argv[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

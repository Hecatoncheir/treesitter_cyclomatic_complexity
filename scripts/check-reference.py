#!/usr/bin/env python3
"""Verify the Go fixtures' EXPECT comments against gocyclo and gocognit.

    scripts/check-reference.py

The fixtures are the test suite's link to the reference implementations. Checked
only by hand, that link rots: a fixture gets edited, its comment does not, and
the suite quietly starts asserting the plugin's own past output instead of the
reference. This keeps the two honest.
"""

from __future__ import annotations

import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURES = sorted((ROOT / "tests" / "fixtures" / "go").glob("*.go"))

# "<score> <package> <name> <file>:<line>:<col>", where <name> may carry a
# receiver such as "(*Cache).Get".
REPORT = re.compile(r"^(\d+)\s+\S+\s+(\S+)\s+\S+$")
EXPECT = re.compile(r"EXPECT\s+(\S+)\s+cc=(\d+)\s+cog=(\d+)")

INSTALL_HINTS = {
    "gocyclo": "go install github.com/fzipp/gocyclo/cmd/gocyclo@latest",
    "gocognit": "go install github.com/uudashr/gocognit/cmd/gocognit@latest",
}


def run_tool(tool: str) -> dict[str, int]:
    """Map bare function name -> score, as reported by `tool`."""
    binary = shutil.which(tool)
    if binary is None:
        sys.exit(f"error: {tool} not found in PATH\n  {INSTALL_HINTS[tool]}")

    output = subprocess.run(
        [binary, *map(str, FIXTURES)],
        capture_output=True,
        text=True,
        check=True,
    ).stdout

    scores: dict[str, int] = {}
    for line in output.splitlines():
        match = REPORT.match(line.strip())
        if match:
            score, name = match.groups()
            scores[name.rsplit(".", 1)[-1]] = int(score)
    return scores


def main() -> int:
    if not FIXTURES:
        sys.exit("error: no Go fixtures found")

    cyclo = run_tool("gocyclo")
    cognit = run_tool("gocognit")

    problems: list[str] = []
    checked = 0

    for path in FIXTURES:
        for line in path.read_text().splitlines():
            match = EXPECT.search(line)
            if not match:
                continue
            name, want_cc, want_cog = match.group(1), int(match.group(2)), int(match.group(3))
            checked += 1

            if name not in cyclo:
                problems.append(f"{path.name} :: {name} -- gocyclo reported nothing")
            elif cyclo[name] != want_cc:
                problems.append(
                    f"{path.name} :: {name} -- fixture says cc={want_cc}, gocyclo says {cyclo[name]}"
                )

            # gocognit omits functions scoring 0, so an absent entry means 0.
            got_cog = cognit.get(name, 0)
            if got_cog != want_cog:
                problems.append(
                    f"{path.name} :: {name} -- fixture says cog={want_cog}, gocognit says {got_cog}"
                )

    if problems:
        print("\n".join(problems))
        print(f"\n{len(problems)} disagreement(s) across {checked} expectations")
        return 1

    print(f"{checked} Go fixture expectations match gocyclo and gocognit")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

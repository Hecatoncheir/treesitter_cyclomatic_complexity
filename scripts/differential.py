#!/usr/bin/env python3
"""Compare this plugin against each language's reference tool over a real corpus.

    scripts/differential.py [language ...]

The fixtures pin a few dozen constructs. This runs the whole thing across
thousands of real functions, which is what catches a rule that is right in
isolation and wrong in company.

A language whose tool or corpus is missing is skipped with a note rather than
failed, so this is usable locally with only some of them installed. CI installs
all of them, and `--strict` turns a skip into a failure so a broken CI step
cannot masquerade as a pass.

Not covered: Dart, which has no working reference tool, and JavaScript, whose
reference is ESLint over Node's own lib/ -- that needs the Node source tree,
which is a heavier fetch than the rest of this put together. Both remain pinned
by fixtures.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

# "<score> <package> <name> <file>:<line>:<col>", as gocyclo and gocognit print.
GO_REPORT = re.compile(r"^(\d+)\s+\S+\s+\S+\s+(.+):(\d+):\d+$")
# luacheck, with the threshold lowered so that everything trips it.
LUA_REPORT = re.compile(
    r"^\s*(.+?):(\d+):\d+: cyclomatic complexity of (.+?) is too high \((\d+) > \d+\)"
)


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, **kwargs)


def mine(lang: str, files: list[str], mode: str) -> dict[tuple[str, int], tuple[int, int]]:
    """This plugin's numbers, keyed by (file, line) -> (cyclomatic, cognitive)."""
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as handle:
        handle.write("\n".join(files) + "\n")
        listing = handle.name
    try:
        result = run(
            ["nvim", "--headless", "-l", str(ROOT / "scripts/dump-complexity.lua"), lang, listing, mode]
        )
    finally:
        os.unlink(listing)

    out: dict[tuple[str, int], tuple[int, int]] = {}
    for line in result.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) == 5:
            out[(parts[0], int(parts[1]))] = (int(parts[2]), int(parts[3]))
    if not out:
        sys.stderr.write(result.stderr[-2000:])
    return out


# --------------------------------------------------------------------- corpora


def go_corpus() -> list[str]:
    goroot = run(["go", "env", "GOROOT"]).stdout.strip()
    if not goroot:
        return []
    src = pathlib.Path(goroot) / "src"
    files: list[str] = []
    for package in ("net/http", "encoding/json", "go/parser", "strings", "time"):
        for path in sorted((src / package).glob("*.go")):
            if not path.name.endswith("_test.go"):
                files.append(str(path))
    return files


def python_corpus() -> list[str]:
    import sysconfig

    stdlib = pathlib.Path(sysconfig.get_paths()["stdlib"])
    files = [
        str(p)
        for p in sorted(stdlib.glob("*.py"))
        if not p.name.startswith("test_")
    ]
    return files[:120]


def lua_corpus() -> list[str]:
    runtime = run(
        ["nvim", "--headless", "-u", "NONE", "-c", "lua io.stdout:write(vim.env.VIMRUNTIME)", "-c", "qa"]
    ).stdout.strip()
    if not runtime:
        return []
    return [str(p) for p in sorted((pathlib.Path(runtime) / "lua").rglob("*.lua"))][:120]


# ----------------------------------------------------------------- references


def go_reference(tool: str, files: list[str]) -> dict[tuple[str, int], int]:
    output = run([tool, *files]).stdout
    found: dict[tuple[str, int], int] = {}
    for line in output.splitlines():
        match = GO_REPORT.match(line.strip())
        if match:
            found[(match.group(2), int(match.group(3)))] = int(match.group(1))
    return found


def radon_reference(files: list[str]) -> dict[tuple[str, int], int]:
    output = run(["radon", "cc", "-j", *files]).stdout
    found: dict[tuple[str, int], int] = {}
    for path, items in json.loads(output).items():
        if isinstance(items, list):
            for item in items:
                if item.get("type") in ("function", "method"):
                    found[(path, item["lineno"])] = item["complexity"]
    return found


def luacheck_reference(files: list[str]) -> dict[tuple[str, int], int]:
    output = run(
        ["luacheck", "--max-cyclomatic-complexity", "1", "--no-color", *files]
    ).stdout
    found: dict[tuple[str, int], int] = {}
    for line in output.splitlines():
        match = LUA_REPORT.match(line)
        # "main chunk" is file-level code, which this plugin does not report as
        # a function.
        if match and "main chunk" not in match.group(3):
            found[(match.group(1), int(match.group(2)))] = int(match.group(4))
    return found


# ------------------------------------------------------------------- the cases

CASES = [
    {
        "id": "go-cyclomatic",
        "lang": "go",
        "tool": "gocyclo",
        "metric": 0,
        "mode": "inline",
        "corpus": go_corpus,
        "reference": lambda files: go_reference("gocyclo", files),
        # The claim in the README is exact, so anything less is a regression.
        "tolerance": 0.0,
    },
    {
        "id": "go-cognitive",
        "lang": "go",
        "tool": "gocognit",
        "metric": 1,
        "mode": "inline",
        "corpus": go_corpus,
        "reference": lambda files: go_reference("gocognit", files),
        # gocognit charges a point for recursion, which needs symbol resolution.
        "tolerance": 2.0,
    },
    {
        "id": "python-cyclomatic",
        "lang": "python",
        "tool": "radon",
        "metric": 0,
        "mode": "separate",
        "corpus": python_corpus,
        "reference": radon_reference,
        # radon does not descend into an `assert` condition.
        "tolerance": 1.0,
    },
    {
        "id": "lua-cyclomatic",
        "lang": "lua",
        "tool": "luacheck",
        "metric": 0,
        "mode": "separate",
        "corpus": lua_corpus,
        "reference": luacheck_reference,
        "tolerance": 1.0,
    },
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("only", nargs="*", help="language ids to run (default: all)")
    parser.add_argument(
        "--strict", action="store_true", help="fail instead of skipping when a tool is missing"
    )
    args = parser.parse_args()

    cases = [c for c in CASES if not args.only or c["id"] in args.only or c["lang"] in args.only]
    failures, skipped = [], []

    print(f"{'case':<20} {'matched':>8} {'exact':>8} {'agreement':>10}  {'limit':>6}")
    print("-" * 60)

    for case in cases:
        if shutil.which(case["tool"]) is None:
            skipped.append(f"{case['id']}: {case['tool']} not installed")
            continue
        files = case["corpus"]()
        if not files:
            skipped.append(f"{case['id']}: no corpus found")
            continue

        reference = case["reference"](files)
        ours = mine(case["lang"], files, case["mode"])
        shared = sorted(set(reference) & set(ours))
        if not shared:
            failures.append(f"{case['id']}: nothing matched between the two")
            continue

        wrong = [k for k in shared if reference[k] != ours[k][case["metric"]]]
        agreement = 100.0 * (1 - len(wrong) / len(shared))
        limit = 100.0 - case["tolerance"]
        status = "" if agreement >= limit else "  FAIL"
        print(
            f"{case['id']:<20} {len(shared):>8} {len(shared) - len(wrong):>8} "
            f"{agreement:>9.2f}% {limit:>6.1f}%{status}"
        )

        if agreement < limit:
            failures.append(f"{case['id']}: {agreement:.2f}% is below {limit:.1f}%")
            for key in wrong[:10]:
                name = ours[key]
                print(
                    f"    {os.path.basename(key[0])}:{key[1]} "
                    f"reference={reference[key]} ours={name[case['metric']]}"
                )

    print()
    for note in skipped:
        print(f"skipped  {note}")
    if args.strict and skipped:
        failures.extend(skipped)

    if failures:
        print()
        for failure in failures:
            print(f"FAIL  {failure}")
        return 1

    print("\nevery case within tolerance")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

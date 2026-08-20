#!/usr/bin/env bash
#
# Build the tree-sitter parsers the test suite needs into a directory that can
# be added to Neovim's runtimepath:
#
#   scripts/install-parsers.sh [target-dir]
#   nvim --cmd "set rtp+=$PWD/.ci/parsers" ...
#
# Grammars are pinned by revision on purpose. The queries in queries/ are
# written against specific node names, so an upstream grammar change must break
# CI visibly rather than silently altering everyone's numbers. Bumping a
# revision here is a deliberate change, reviewed together with any query edits
# it makes necessary.
set -euo pipefail

TARGET="${1:-.ci/parsers}"
mkdir -p "$TARGET/parser"
TARGET="$(cd "$TARGET" && pwd)"

# lang|repo|revision
GRAMMARS=(
  "go|https://github.com/tree-sitter/tree-sitter-go|2346a3ab1bb3857b48b29d779a1ef9799a248cd7"
  "dart|https://github.com/UserNobody14/tree-sitter-dart|be07cf7118d3dba06236a3f19541685a68209934"
  # tree-sitter-python v0.25.0, resolved to its commit: a tag can move.
  "python|https://github.com/tree-sitter/tree-sitter-python|293fdc02038ee2bf0e2e206711b69c90ac0d413f"
  # tree-sitter-javascript v0.25.0, resolved to its commit: a tag can move.
  "javascript|https://github.com/tree-sitter/tree-sitter-javascript|44c892e0be055ac465d5eeddae6d3e194424e7de"
)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for entry in "${GRAMMARS[@]}"; do
  IFS='|' read -r lang repo revision <<< "$entry"
  out="$TARGET/parser/$lang.so"

  if [ -f "$out" ]; then
    echo "==> $lang: already built"
    continue
  fi

  echo "==> $lang: fetching $revision"
  src="$WORK/$lang"
  mkdir -p "$src"
  git -C "$src" init -q
  git -C "$src" remote add origin "$repo"
  git -C "$src" fetch -q --depth 1 origin "$revision"
  git -C "$src" checkout -q FETCH_HEAD

  # A grammar may ship an external scanner, in C or in C++. The C++ case has to
  # be linked with the C++ driver or the standard library goes missing.
  sources=("$src/src/parser.c")
  compiler=cc
  if [ -f "$src/src/scanner.c" ]; then
    sources+=("$src/src/scanner.c")
  elif [ -f "$src/src/scanner.cc" ]; then
    sources+=("$src/src/scanner.cc")
    compiler=c++
  fi

  echo "==> $lang: compiling ${sources[*]##*/}"
  "$compiler" -o "$out" -shared -fPIC -Os -I "$src/src" "${sources[@]}"
done

echo
echo "parsers in $TARGET/parser:"
ls -la "$TARGET/parser"

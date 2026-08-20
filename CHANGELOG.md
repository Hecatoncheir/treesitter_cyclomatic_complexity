# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-08-20

First release.

### Added

- Cyclomatic and cognitive complexity per function, computed from tree-sitter
  with no external tools.
- End-of-line virtual text (`● CC 12`) coloured by threshold, through the
  `CyclomaticLow`/`Medium`/`High`/`VeryHigh` highlight groups, which link to
  the `Diagnostic*` groups so they follow the colorscheme.
- Support for **Go** and **Dart**. All language rules live in
  `queries/<lang>/cyclomatic.scm` and are resolved by runtimepath, so a language
  can be added, or the shipped rules overridden, without touching Lua.
- Optional `vim.diagnostic` integration, which routes complexity into Trouble,
  the quickfix list, the statuscolumn and `]d`.
- `:Cyclomatic` with `toggle`, `enable`, `disable`, `refresh`, `reload`,
  `metric`, `list`, `project` and `info` subcommands.
- Buffer and project-wide pickers, using `snacks.picker` when present and the
  quickfix list otherwise. The project scan runs off the main loop in chunks.
- A lualine component showing the complexity of the function under the cursor.
- `doc/CONTRACT.md`, documenting the query capture vocabulary and the two
  grammar shapes that fail silently when they are got wrong.

### Development

- A dependency-free test suite (50 cases) covering the metric engine, rendering,
  diagnostics and the command surface, runnable with nothing but Neovim and two
  compiled parsers.
- CI across Neovim 0.10, stable and nightly, with stylua and luacheck.
- `scripts/install-parsers.sh`, which builds the Go and Dart grammars at pinned
  revisions so a grammar change breaks CI visibly rather than quietly altering
  everyone's numbers.
- `scripts/check-reference.py`, which proves the fixtures' stated gocyclo and
  gocognit values are still what those tools produce.
- Tagging `vX.Y.Z` publishes a GitHub release, with notes taken from this file.

### Verified

- Cyclomatic complexity matches `gocyclo` on **1620 of 1620** functions from the
  Go standard library.
- Cognitive complexity matches `gocognit` on **1106 of 1118**; every difference
  is recursion, which needs symbol resolution that tree-sitter does not provide.

[Unreleased]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/releases/tag/v0.1.0

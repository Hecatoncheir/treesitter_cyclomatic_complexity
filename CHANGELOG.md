# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-08-20

### Added

- `virtual_text.label` makes the text before the number configurable without
  replacing the whole `format` function. It takes a table keyed by metric --
  `:Cyclomatic metric` switches metrics while annotations are on screen, so a
  single fixed string would start lying the moment it was flipped -- and also
  accepts a plain string for both, or `''` to show just the number.

### Fixed

- The default annotation no longer leaves a stray leading space when `prefix` is
  set to `''`. Its parts are joined rather than formatted into a fixed template,
  so an empty prefix or label simply drops out.

## [0.2.0] - 2026-08-20

### Added

- **Lua support** (`queries/lua/cyclomatic.scm`). Cyclomatic complexity matches
  `luacheck` on 911 of 917 functions across Neovim's own runtime, measured in
  the `separate` nesting mode luacheck uses.
- `doc/ADDING-A-LANGUAGE.md`: a worked example of adding a language, following
  the Lua path end to end -- reading the grammar, the two places its shape
  forced the query away from the Go one, validating against a reference tool,
  and the failure modes that produce wrong numbers instead of errors.

## [0.1.1] - 2026-08-20

### Changed

- **The minimum supported Neovim is 0.11, not 0.10.** 0.1.0 claimed 0.10 on the
  strength of an API audit; CI then showed that current Go and Dart grammars
  compile to tree-sitter ABI 15, which 0.10 cannot load -- it accepts 13 to 14.
  Nothing in the plugin's own code needed 0.11. The floor is now tested on every
  run rather than reasoned about.

### Fixed

- A failed query lookup reported its reason only once. Every call after the
  first fell back to a generic "no cyclomatic query for <lang>", hiding messages
  worth acting on -- an ABI mismatch above all. The reason is now cached with
  the failure and reported every time.

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

[Unreleased]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/releases/tag/v0.1.0

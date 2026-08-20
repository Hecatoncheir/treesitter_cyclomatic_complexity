# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.9.2] - 2026-08-20

### Fixed

- A query or parser that arrived after first use was never picked up. Failed
  lookups were cached alongside successful ones, so a parser installed
  mid-session, or a query on a runtimepath entry added late, left the plugin
  reporting it missing until `:Cyclomatic reload`. Only successes are cached
  now: Neovim memoizes its own query lookups, so a miss costs about two
  microseconds and the cache was buying nothing.

### Added

- The README and `:help cyclomatic` now say that no `dependencies` entry is
  needed, nvim-treesitter included. Nothing here requires it -- the plugin uses
  `vim.treesitter` from Neovim itself and finds parsers and queries on the
  runtimepath -- and declaring it only forces it to load whenever this plugin
  does. The stale-failure bug above was the one thing that could have made a
  load-order dependency look necessary.

## [0.9.1] - 2026-08-20

### Added

- `scripts/differential.py`, and a CI job that runs it. It compares the plugin
  against each language's reference tool over that language's own standard
  library -- around 9000 functions, where the fixtures pin a few dozen -- which
  is what catches a rule that is right in isolation and wrong in company. Go
  cyclomatic is held to exact agreement; the others carry a tolerance covering
  their documented differences.
- `scripts/dump-complexity.lua`, which prints the plugin's numbers for a list
  of files, in either nesting mode. Reference tools disagree about whether a
  closure belongs to the function around it, so a comparison has to be made in
  whichever mode the tool itself uses.

### Notes

- `--strict` makes a missing tool a failure rather than a skip, so the CI step
  cannot pass by quietly checking nothing. Verified both ways, along with the
  regression it is meant to catch.
- Dart and JavaScript are not covered: Dart has no working reference tool, and
  JavaScript's needs the Node source tree. Both remain pinned by fixtures.

## [0.9.0] - 2026-08-20

### Added

- Analysis now reuses the functions tree-sitter did not have to rebuild,
  roughly halving the cost of a recompute on a large file: 25.7 ms to 13.2 ms
  on `net/http/server.go`, 22.0 to 9.1 on `transport.go`. Profiling came
  first, and corrected the guess: the traversal itself is the cost, not the
  lookups inside it, so the only way to make it cheaper is to visit fewer
  nodes.
- `analyzer.forget(bufnr)` drops the reuse cache for one buffer, or for all of
  them with no argument. Buffers release it on deletion.

### Notes

- The cache keys on tree-sitter node ids, which survive an incremental reparse
  for any subtree that did not change. Rebuilding a subtree rebuilds its
  ancestors, so an unchanged id means nothing inside changed either -- checked
  rather than assumed, including for an edit buried inside a closure.
- Rows are rebased rather than trusted: inserting a line above a function
  shifts its rows without touching its id.
- A stale entry would produce a plausible wrong number rather than an error, so
  every case in the new suite compares the incremental answer against one
  computed from scratch, across shifts, edits inside a function, added and
  removed functions, both nesting modes, and after a query reload.
- `:Cyclomatic explain` takes the slow path deliberately. It records a row per
  contribution, which rebasing would have to follow, and it runs once on
  demand.

## [0.8.0] - 2026-08-20

### Added

- **JavaScript support** (`queries/javascript/cyclomatic.scm`). Cyclomatic
  complexity matches ESLint's `complexity` rule on all 6766 functions across
  Node.js's own `lib/` (v22.9.0), measured in `nested_functions = 'separate'`,
  the mode ESLint always reports in. The same "lower the threshold until
  everything trips it" trick used for luacheck settled two rules the grammar
  alone would not have: optional chaining (`obj?.a?.b?.()`) is not a branch,
  but the logical assignment operators `??=`, `||=` and `&&=` are, exactly
  like `??`, `||` and `&&`. `else` is never a direct child of `if_statement`
  here, unlike Go and Dart — both a plain `else` and an `else if` sit inside
  an intermediate `else_clause` wrapper that carries no score of its own.
  Closures are named from their binding wherever JavaScript allows one: a
  `const`, a plain or prototype assignment, an object-literal property, or a
  class field holding an arrow function.
- The JavaScript grammar in `scripts/install-parsers.sh`, pinned to the
  commit behind its `v0.25.0` tag rather than the tag itself.

## [0.7.0] - 2026-08-20

### Added

- `:Cyclomatic explain` accounts for the score of the function under the
  cursor: every point counted, what it contributed to each metric, and how
  deeply it was nested. A number alone cannot distinguish a disagreement about
  the rules from a bug in the query. Operators are listed apart from their
  runs, since `a && b && c` costs two cyclomatically and one cognitively, and a
  report that hid that would look wrong. The suite checks the account
  reconciles with the score for every function in every fixture, in both
  nesting modes.
- `:help cyclomatic`. The documentation was Markdown only, which is not where
  Neovim users read it.

## [0.6.0] - 2026-08-20

### Added

- **Python support** (`queries/python/cyclomatic.scm`). Cyclomatic complexity
  matches `radon` on 2134 of 2138 functions across the Python standard library;
  the four differences are all `assert`, where radon counts the statement but
  not the boolean operator inside it, while counting that same operator in an
  `if` or a `return`.
- A quickstart at the top of `doc/ADDING-A-LANGUAGE.md`: the whole job on
  Python, command by command, including the three rules that cannot be guessed
  from the grammar -- `for … else` opens a path where `if … else` does not, a
  comprehension is a loop, and `assert` is a conditional raise -- and how a
  disagreement over a lambda turned out to be a query decision rather than a
  configuration one.
- The Python grammar in `scripts/install-parsers.sh`, pinned to the commit
  behind its `v0.25.0` tag rather than the tag itself.

## [0.5.1] - 2026-08-20

### Added

- A screenshot in the README, in place of the ASCII mock-up that stood for one.

### Changed

- The default `virtual_text.prefix` is a Nerd Font glyph. Without a patched font
  it renders as a placeholder box, so both the README and the option itself now
  say so and name `●` as the fallback.

### Fixed

- Specs no longer assert on the default prefix. Changing a cosmetic default
  broke seven of them, which is a test problem rather than a real one: those
  cases now set the prefix they expect.

## [0.5.0] - 2026-08-20

### Added

- `:checkhealth cyclomatic`. A missing parser, a parser whose tree-sitter ABI
  the running Neovim cannot load, and a query whose node names no longer exist
  all used to surface as the same `no cyclomatic query for <lang>`, several
  steps from the cause. Each is now named and given its own remedy, alongside a
  configuration check and a list of which open buffers are being measured.

### Fixed

- An invalid `metric` no longer breaks rendering. It surfaced as `attempt to
  compare number with nil` from the renderer, nowhere near the typo that caused
  it; `setup()` now validates its options, says what is wrong, and falls back to
  a usable value instead of leaving the plugin broken.

## [0.4.1] - 2026-08-20

### Added

- `tests/fixtures/dart/constructs.dart`, pinning 17 Dart constructs one per
  function, cross-checked against `dart_code_metrics` 5.7.6. It confirms 13
  outright; on the four it disputes -- `do`/`while`, two- and three-case
  `switch`, and `yield` -- it also contradicts `gocyclo` and `luacheck` scoring
  the equivalent construct, so it is the outlier. It finds no decision at all in
  a three-way switch. Provenance is recorded per construct in the fixture and
  summarised in the README.

## [0.4.0] - 2026-08-20

### Added

- A query scaffolder: `:Cyclomatic scaffold [lang]` for the current buffer, or
  `scripts/scaffold-query.lua` for files. It reads parsed samples and emits a
  draft `cyclomatic.scm` that is always valid query syntax, reports the
  constructs the samples never exercised, and names the grammar shapes that
  fail silently -- a body held in a sibling rather than a child above all.
  Unedited, its Go draft scores 100% against gocyclo across 1619
  standard-library functions, and 79% against gocognit.

### Fixed

- `tests/tools/dump.lua` now prints anonymous children that occupy a field.
  `node:sexpr()` omits anonymous nodes entirely, so an operator held in an
  `operator:` field is invisible there.
- Boolean operators are matched as anonymous tokens rather than through the
  `operator:` field, in the Go query as well as the Lua one. Whether a grammar
  exposes that field depends on its version -- the Lua grammar bundled with
  Neovim 0.12 has it, the one bundled with 0.11 does not, and a query written
  against it fails to parse there. The token form works either way.

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

[Unreleased]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.9.2...HEAD
[0.9.2]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/releases/tag/v0.1.0

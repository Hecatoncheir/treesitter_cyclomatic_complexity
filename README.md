# treesitter_cyclomatic_complexity

[![CI](https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/actions/workflows/ci.yml/badge.svg)](https://github.com/Hecatoncheir/treesitter_cyclomatic_complexity/actions/workflows/ci.yml)
[![Neovim](https://img.shields.io/badge/Neovim-0.11%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

Cyclomatic and cognitive complexity for Neovim, computed entirely from
tree-sitter. Pure Lua, no external binaries, no LSP.

Complexity is shown as end-of-line virtual text on each function's signature,
coloured by how bad it is:

```
func (s *Server) Handle(w http.ResponseWriter, r *Request) error {   ● CC 14
```

**Languages: Go and Dart.** Adding another is a query file, not code — see
[doc/CONTRACT.md](doc/CONTRACT.md).

## Why this can be trusted

Cyclomatic complexity is a purely syntactic metric, which is exactly what a
parse tree can answer. The numbers are checked against the reference tools for
Go on 1620 functions from the Go standard library (`net/http`, `encoding/json`,
`go/parser`, `strings`, `time`):

| Metric | Reference | Agreement |
| --- | --- | --- |
| Cyclomatic | `gocyclo` | **1620 / 1620 exact** |
| Cognitive | `gocognit` | **1106 / 1118 exact** |

All 12 cognitive differences are recursion, which `gocognit` charges a point for
and this plugin does not — see [Limitations](#limitations).

## Install

lazy.nvim:

```lua
{
  'Hecatoncheir/treesitter_cyclomatic_complexity',
  main = 'cyclomatic',
  event = { 'BufReadPost', 'BufNewFile' },
  opts = {},
}
```

`main = 'cyclomatic'` is required — the Lua module name differs from the repo
name. Needs Neovim 0.11+ and a tree-sitter parser for the language you are
editing (`go` and `dart`). Neovim 0.10 loads only tree-sitter ABI 13-14, which
current Go and Dart grammars have outgrown.

## Configuration

Defaults, all optional:

```lua
opts = {
  -- Which metric drives the virtual text: 'cyclomatic' or 'cognitive'.
  metric = 'cyclomatic',

  -- 'inline'   closures count toward the enclosing function (what gocyclo does)
  -- 'separate' every closure is reported on its own
  nested_functions = 'inline',

  -- Colour buckets: <=low green, <=medium yellow, <=high red, above that bold red.
  thresholds = { low = 5, medium = 10, high = 20 },

  virtual_text = {
    enabled = true,
    min_complexity = 4,   -- leave trivial functions unannotated
    prefix = '●',
    format = function(entry, cfg)
      local label = cfg.metric == 'cognitive' and 'COG' or 'CC'
      return string.format('%s %s %d', cfg.virtual_text.prefix, label, entry[cfg.metric])
    end,
    position = 'eol',
    priority = 100,
  },

  -- Off by default. Turning this on routes complexity into Trouble, the
  -- quickfix list, the statuscolumn and ]d for free.
  diagnostics = { enabled = false, min_complexity = 11 },

  events = { 'BufReadPost', 'BufWritePost', 'TextChanged', 'InsertLeave' },
  debounce = 250,

  filetypes = nil,          -- nil = every language that has a query
  exclude_filetypes = {},
  max_filesize = 512 * 1024,
}
```

### Colours

Four highlight groups, linked to the `Diagnostic*` groups by default so they
follow your colorscheme. Override any of them:

```lua
vim.api.nvim_set_hl(0, 'CyclomaticLow', { fg = '#6f7d68' })
vim.api.nvim_set_hl(0, 'CyclomaticMedium', { fg = '#d8a657' })
vim.api.nvim_set_hl(0, 'CyclomaticHigh', { fg = '#ea6962' })
vim.api.nvim_set_hl(0, 'CyclomaticVeryHigh', { fg = '#ea6962', bold = true })
```

## Commands

| Command | Effect |
| --- | --- |
| `:Cyclomatic` | toggle annotations |
| `:Cyclomatic enable` / `disable` | ... explicitly |
| `:Cyclomatic refresh` | recompute the current buffer |
| `:Cyclomatic metric [cyclomatic\|cognitive]` | switch metric, or flip it with no argument |
| `:Cyclomatic list` | functions in this buffer, most complex first |
| `:Cyclomatic project [root]` | same across the project (async) |
| `:Cyclomatic info` | language, support status, score at the cursor |
| `:Cyclomatic reload` | re-read query files after editing one |

`list` and `project` use `snacks.picker` when it is installed and fall back to
the quickfix list otherwise.

## lualine

```lua
sections = { lualine_x = { require('cyclomatic.lualine') } }
```

Shows the complexity of the function under the cursor, coloured by the same
buckets.

## API

```lua
local cc = require('cyclomatic')

cc.get(bufnr)        -- full analysis: { lang, entries, file_level }
cc.current()         -- entry under the cursor, or nil
cc.supported(bufnr)  -- is there a query for this buffer's language?
cc.refresh(bufnr)
cc.toggle(bufnr)     -- omit bufnr for global
```

Each entry is `{ name, row, end_row, cyclomatic, cognitive, nested }`, with
0-indexed rows.

## What counts

Cyclomatic complexity starts at 1 per function and adds one for each `if`,
`else if`, loop, non-default `case`, `catch`/`on` handler, ternary, and each
`&&`, `||` or `??`. A plain `else` and a `default:` add nothing — they
introduce no independent path. This is gocyclo's rule set exactly.

Cognitive complexity follows SonarSource: branches cost more the deeper they
are nested, `else` costs a flat point, and a run of the same boolean operator
costs one point rather than one per operator.

Full rules, and the capture vocabulary that expresses them, are in
[doc/CONTRACT.md](doc/CONTRACT.md).

## Adding a language

Write `queries/<lang>/cyclomatic.scm`. No Lua changes are needed — Neovim finds
the file by runtimepath, which also means you can override the shipped rules by
putting your own version in `~/.config/nvim/queries/<lang>/cyclomatic.scm`.

Inspect a grammar with:

```bash
nvim --headless -l tests/tools/dump.lua path/to/file.rs rust
```

Then add a fixture under `tests/fixtures/` with `EXPECT <name> cc=<n> cog=<n>`
comments and run the suite.

## Tests

The suite needs nothing but Neovim and the two tree-sitter parsers. Build the
parsers once, then run it:

```bash
scripts/install-parsers.sh
```

```bash
nvim --headless -u NONE --cmd "set rtp+=$PWD/.ci/parsers" -l tests/run.lua
```

With the parsers already on your runtimepath, `nvim --headless -l tests/run.lua`
is enough. Pass a name to run a subset — `... -l tests/run.lua analyzer`.

Cases live in `tests/spec/`. Fixture expectations live beside the code they
describe, as `EXPECT <name> cc=<n> cog=<n>` comments, and the Go numbers are the
values gocyclo and gocognit produce for those same files. That claim is itself
checked, so the suite cannot drift into asserting only its own past output:

```bash
scripts/check-reference.py
```

CI runs the suite against Neovim 0.11, stable and nightly, plus stylua,
luacheck, and the reference check above. Grammars are pinned by revision in
`scripts/install-parsers.sh` — a grammar change has to break CI visibly rather
than quietly altering everyone's numbers.

## Releasing

Tagging `vX.Y.Z` builds a GitHub release automatically. The notes come from the
matching `CHANGELOG.md` section, and a tag without one fails the workflow before
anything is published:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

## Limitations

These are deliberate, and all of them follow from what a parse tree can and
cannot know:

- **Recursion is not counted.** SonarSource charges a point for a recursive
  call; detecting one needs symbol resolution, which tree-sitter does not do.
  Matching on the function's name instead is worse than not trying: it is
  exactly what makes `gocognit` report complexity 1 for
  `func (d dirEntryDirs) len() int { return len(d) }`, where the `len` being
  called is the builtin.
- **Declarations without a body are skipped**, such as Go's `//go:linkname`
  forward declarations. There is no code to measure.
- **Dart wildcard switch arms are counted.** In a Dart 3 pattern switch, `_ =>`
  is a `switch_expression_case` like any other, so unlike a `default:` clause it
  cannot be excluded structurally.
- **Macro bodies are opaque.** Branches generated inside a macro are invisible;
  this matters for Rust and C, not for Go or Dart.
- **Only the root language of a buffer is analyzed** — injected languages, such
  as SQL inside a string, are not.

## License

MIT

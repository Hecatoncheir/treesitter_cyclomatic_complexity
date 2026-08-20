# Adding a language

Adding a language means writing one file:

```
queries/<lang>/cyclomatic.scm
```

No Lua changes. Neovim resolves it through
`vim.treesitter.query.get(lang, 'cyclomatic')`, which searches the whole
runtimepath, so the engine picks it up as soon as it exists — and a user can
override yours by putting their own version in
`~/.config/nvim/queries/<lang>/cyclomatic.scm`.

What follows is the real path taken to add Lua, including the two places where
the obvious query would have been wrong. The capture vocabulary itself is in
[CONTRACT.md](CONTRACT.md); this is how to arrive at it for a new grammar.

---

## 1. Check the parser

```bash
nvim --headless -u NONE -c "lua print(vim.inspect(vim.api.nvim_get_runtime_file('parser/lua.so', true)))" -c qa
```

An empty list means the parser is missing — install it however you normally do
(`nvim-treesitter`, or `scripts/install-parsers.sh` for the two this repo builds
itself). Lua needs nothing: Neovim bundles it.

## 2. Read the grammar

This is the step worth spending time on. Write a small file using the
constructs that branch, and dump its tree:

```bash
nvim --headless -l tests/tools/dump.lua /tmp/sample.lua lua 4
```

For an `if / elseif / else` chain, Lua answers:

```
function_declaration  [1:9]
| name: identifier  [1:1]  classify
| body: block  [2:8]
| | if_statement  [2:8]
| | | condition: binary_expression  [2:2]  n < 0 and flag
| | | consequence: block  [3:3]
| | | alternative: elseif_statement  [4:5]
| | | alternative: else_statement  [6:7]
```

Three facts come straight out of that, and each one changes the query:

- `function_declaration` has `body:` as a **child**. In Dart it is a *sibling*
  of the signature, which is why that query anchors the two with `.` — see
  `queries/dart/cyclomatic.scm`.
- `elseif` and `else` are **node types of their own**. In Go and Dart an
  `else if` is just an `if_statement` in the `alternative:` field.
- `binary_expression` has `left:` and `right:` but **no `operator:` field**. Go
  has one, which is how `queries/go/cyclomatic.scm` picks out `&&` and `||`.
  That technique does not transfer.

Confirm anything the dump leaves ambiguous with the s-expression of a single
node type, which shows field names exactly as a query must spell them.

## 3. Write the query

Start from `queries/go/cyclomatic.scm` and adapt. The mechanical parts first:

```scheme
(function_declaration
  name: (_) @function.name
  body: (block) @function.body)

(function_definition
  body: (block) @function.body)

(if_statement) @decision
(for_statement) @decision
(while_statement) @decision
(repeat_statement) @decision
```

`name: (_)` rather than `name: (identifier)` is deliberate: Lua puts an
`identifier`, a `dot_index_expression` (`M.helper`) or a
`method_index_expression` (`M:method`) in that field, and the wildcard captures
all three with a label that reads correctly.

Now the two adaptations the grammar forced.

**`elseif` needs both captures.** In Go, the else-if node matches
`(if_statement) @decision` already, and `@chained` is layered on top of it. Lua's
`elseif_statement` matches no other pattern, so it needs both, written as two
patterns over the same node:

```scheme
(elseif_statement) @decision
(elseif_statement) @chained
```

`@chained` is a modifier, not a rule. On its own it counts nothing.

**`and`/`or` are matched as anonymous children**, since there is no field to
select them by:

```scheme
((binary_expression "and") @decision.flat)
((binary_expression "or") @decision.flat)
```

Note the capture is on the **expression**, not on the token. Capturing
`(binary_expression "and" @decision.flat)` also compiles, and gives the right
cyclomatic number — but it breaks cognitive complexity, which charges one point
per *run* of the same operator within an expression. The analyzer groups
operators by their outermost enclosing captured expression; capture the tokens
and every operator becomes its own group, so `a and b and c` costs 2 instead
of 1.

Finally, the pieces that count for only one metric:

```scheme
(else_statement) @cognitive.flat   ; no new path, but a point to read
(goto_statement) @cognitive.flat   ; Lua's only jump
```

## 4. Check against a reference tool

Do not trust your own arithmetic. Most languages have an established checker,
and matching it is both a correctness proof and a decision about *whose* rules
you are implementing.

For Lua that is `luacheck`, which reports complexity when you set the threshold
low enough that everything trips it:

```bash
luacheck --max-cyclomatic-complexity 1 --no-color path/to/file.lua
```

Run it over a real corpus — Neovim's own runtime is right there — and diff
against the plugin. The first run scored **87%**, with every difference in the
same direction and 259 functions reported by luacheck that the plugin never
emitted at all.

That pattern is the signature of a *model* difference, not a rule bug: luacheck
reports every closure as a function of its own, which is this plugin's
`nested_functions = 'separate'`. The default is `'inline'`, matching gocyclo.
Re-running in the matching mode gave **99.35%** (911 of 917).

So: before concluding your query is wrong, check that you are comparing like
with like. Reference tools disagree with each other about nesting, about whether
`default:` counts, and about recursion — see the Limitations section of the
README for the ones this plugin takes a position on.

## 5. Add a fixture

Fixtures carry their own expectations as comments, and the runner treats a
function it finds without an expectation as a failure, so a query that starts
matching something new cannot slip through:

```lua
-- EXPECT conditions cc=5 cog=5
local function conditions(n, a, b)
  if n < 0 and a then
    return -1
  elseif n == 0 or b then
    return 0
  else
    return 1
  end
end
```

Take the `cc` numbers from the reference tool where it agrees with the mode you
ship; compute `cog` by hand, since cognitive complexity has far fewer
implementations. Include at least one function of each shape the grammar has —
for Lua that meant `function M.f()`, `function M:f()`, a closure, the
`a and b or c` ternary idiom, and `goto`.

Write the same branch shape as the Go and Dart fixtures use, too. The numbers
must not depend on which language the code is written in, and a fixture that
states so is the cheapest way to keep it true.

Register the extension in `tests/spec/fixtures_spec.lua`:

```lua
local EXTENSIONS = { go = 'go', dart = 'dart', lua = 'lua' }
```

Then:

```bash
nvim --headless -l tests/run.lua fixtures
```

## 6. Wire it into CI

If the parser is bundled with Neovim, as Lua's is, there is nothing to do. If it
is not, add the grammar to `scripts/install-parsers.sh` **pinned by revision**:
the queries are written against specific node names, so a grammar change has to
break CI visibly rather than quietly altering everyone's numbers.

Finally, update the language list in `README.md` and add an entry to
`CHANGELOG.md`.

---

## Traps

All of these fail silently — no error, just wrong numbers. They are worth
checking explicitly rather than waiting to notice.

| Symptom | Cause |
| --- | --- |
| Every function reports **CC = 1** | `@function.body` never matched. Usually the body is a *sibling* of the signature, not a child. |
| A whole file reports nothing | The query did not parse, or no `@function.body` pattern matched at all. `:Cyclomatic info` says whether a query was found. |
| Boolean chains cost too much cognitively | `@decision.flat` was captured on the operator token instead of the expression. |
| `else if` counted as a fresh nesting level | Missing `@chained`. |
| `default:` / wildcard arms inflate the count | Capture the specific case node, not the generic one, if the grammar distinguishes them. |
| Counts drift after an upgrade | An unpinned grammar changed node names. |

And one that fails loudly, but confusingly: `ABI version mismatch ... supported
between 13 and 14, found 15` means the parser is newer than the running Neovim,
not that anything is wrong with the query.

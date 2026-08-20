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

Two routes through this. The **Quickstart** below is the whole job on Python,
command by command, and is what to follow when adding a language. The numbered
sections after it are the same ground at reading pace, on Lua, including the
place where the obvious reading of the grammar was wrong. The capture vocabulary
itself is in [CONTRACT.md](CONTRACT.md).

---

## Quickstart: Python, end to end

This is verbatim how Python support in this repository was added, including the
three rules that would not have been guessed and the one place the reference
tool is left behind.

### Get a parser

```bash
nvim --headless -u NONE -c "lua print(#vim.api.nvim_get_runtime_file('parser/python.so', true))" -c qa
```

Zero means install it. For a language the test suite will cover, add the grammar
to `scripts/install-parsers.sh` **pinned to a commit**, and resolve any tag
yourself — a tag can be moved, a commit cannot:

```bash
git ls-remote https://github.com/tree-sitter/tree-sitter-python v0.25.0^{}
```

### Write samples, then scaffold

Two files, covering everything that branches: `if`/`elif`/`else`, `and`/`or`,
loops, `try`, comprehensions, ternaries, `match`, `lambda`, a nested `def`.

```bash
nvim --headless -l scripts/scaffold-query.lua python basics.py expressions.py
```

The draft comes back nearly complete — `function_definition`, the branch nodes,
`match_statement` with its `case_clause`, and `((boolean_operator "and"))` — and,
more usefully, it separates out what it will not decide for you:

```
; ==== PROBABLY PARTS, BUT CHECK ====
; These name a piece of a construct in most grammars -- but not all:
; Python's elif_clause is a real branch. Uncomment what belongs.
;; (elif_clause) @decision
;; (except_clause) @decision
;; (for_in_clause) @decision
;; (if_clause) @decision
```

All four of those turn out to be real branches in Python. Which brings us to how
you find that out.

### Ask the reference tool, one construct at a time

`radon` is Python's. Do not run it on your samples and squint at the totals —
write one function per construct, so a disagreement points at exactly one rule:

```bash
radon cc -s probe.py
```

Twenty short functions later, three answers that no amount of staring at the
grammar would have produced:

| Construct | radon | Why |
| --- | --- | --- |
| `for … else` | counts | the `else` runs only if the loop finished without `break` |
| `if … else` | does not | as in every other language here |
| `[x for x in xs]` | counts | a comprehension is a loop, and each extra clause is another path |
| `assert n > 0` | counts | a conditional raise |

The first two share a node type — Python's grammar gives both `alternative:
(else_clause)` — so they are told apart by their parent:

```scheme
(if_statement alternative: (else_clause) @cognitive.flat)   ; no new path
(for_statement alternative: (else_clause) @decision)        ; a new path
(while_statement alternative: (else_clause) @decision)
(try_statement (else_clause) @decision)
```

Python also does something no other grammar here manages: it makes the
fall-through arm identifiable. A wildcard `case _` has a `case_pattern` with no
named child, so requiring one excludes it — where Dart's equivalent has to be
counted and documented as a known excess:

```scheme
((case_clause (case_pattern (_))) @cyclomatic)
```

### Run it against a corpus, and read the disagreements

```bash
radon cc -j $(cat corpus.txt) > radon.json
```

The first full run scored **99.77%** on 2138 functions of the Python standard
library, with five disagreements. Four were `assert`. One was not, and it was
the interesting one: `traceback.py` counted one *lower* than radon.

The cause was a lambda. radon inlines a lambda's branches into the function
around it, while still reporting a nested `def` separately — a mixed model that
neither `inline` nor `separate` reproduces. The fix was not a mode but a query
decision: a lambda is simply not captured as a function.

```scheme
; A lambda is deliberately *not* a function here. Python restricts it to a
; single expression, so it can never be complex enough to deserve an entry of
; its own, and reporting `<closure> cc=2` for `key=lambda x: x or 0` is noise.
```

That took it to **99.81%**, and the four that remain are all `assert`: radon
counts the statement but does not descend into its condition, scoring
`assert a and b` the same as `assert a` — while counting that same `and` in an
`if` or a `return`. Being inconsistent with itself is what decides it; the
operator is counted here, and the fixture says so out loud.

### Pin it

```lua
local EXTENSIONS = { go = 'go', dart = 'dart', lua = 'lua', py = 'python' }
```

Then a fixture whose `cc` values are the reference tool's, with the one
deliberate departure marked as such, and:

```bash
nvim --headless -l tests/run.lua fixtures
```

Total: one query file, one fixture, two lines elsewhere. The scaffolder wrote
most of the first; the reference tool decided everything that mattered.

## 1. Check the parser

```bash
nvim --headless -u NONE -c "lua print(vim.inspect(vim.api.nvim_get_runtime_file('parser/lua.so', true)))" -c qa
```

An empty list means the parser is missing — install it however you normally do
(`nvim-treesitter`, or `scripts/install-parsers.sh` for the two this repo builds
itself). Lua needs nothing: Neovim bundles it.

## 2. Generate a draft

Rather than starting from an empty file, let the plugin read the grammar for
you:

```bash
nvim --headless -l scripts/scaffold-query.lua lua sample1.lua sample2.lua
```

or, from a buffer of the language in question, `:Cyclomatic scaffold`.

It walks the parsed samples, classifies node types by role, and emits a draft
query — always valid syntax, so it can be saved and run before a line of it is
reviewed. On Go's own fixtures the unedited draft scores **100% against
gocyclo** across 1619 standard-library functions, and 79% against gocognit; the
cognitive gap is the part that cannot be guessed from tree shape, covered in
step 4.

Two things it does that are worth the trouble on their own. It reports the
constructs your samples never used —

```
; ==== NOT PRESENT IN THE SAMPLE ====
; * no boolean operators (`a && b`)
```

— because a rule cannot be guessed from code that does not exercise it, and a
missing rule is silent. And it names the shapes that fail silently:

```
; ==== WOULD OTHERWISE HAVE FAILED SILENTLY ====
; * function_signature keeps its body in a SIBLING (function_body), not a child
;   -- nesting them in a query matches nothing and reports CC=1 everywhere
```

Pass several samples. The draft is only as complete as the code it saw.

Everything it emits is a guess. The rest of this guide is how to check them.

## 3. Read the grammar

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
- `binary_expression` keeps `and`/`or` as an **anonymous child**. Whether it
  *also* exposes them through an `operator:` field depends on the version of the
  grammar, which is a trap worth spelling out.

Three things collide in that last point, and each one can mislead on its own.

**`node:sexpr()` omits anonymous nodes entirely, field names included.** Lua's
operator is an anonymous token, so its sexpr reads

```
(binary_expression left: (identifier) right: (identifier))
```

which looks like a node with no operator field whether or not it has one.
`tests/tools/dump.lua` prints anonymous children that fill a field, so use it —
or probe directly with `node:field('operator')`.

**The field's existence varies by grammar version.** The Lua grammar bundled
with Neovim 0.12 has an `operator:` field; the one bundled with 0.11 does not,
and a query written against it fails to *parse* there. So even having checked,
do not depend on it.

**The anonymous form works either way**, in both grammars and both versions:

```scheme
((binary_expression "and") @decision.flat)
```

That is why every query here matches operators as tokens, Go's `&&` included,
even where a field is available.

Dart differs again, and this one is not a version accident: its operator is a
*named* `logical_and_operator` child with no field at all, so
`queries/dart/cyclomatic.scm` captures the whole expression instead.

## 4. Refine the draft

The draft from step 2 already has the mechanical parts:

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

**`and`/`or` are matched as anonymous tokens**, for the portability reason
above:

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

## 5. Check against a reference tool

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

## 6. Add a fixture

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

## 7. Wire it into CI

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

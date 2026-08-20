# Query contract

Everything language-specific lives in `queries/<lang>/cyclomatic.scm`. The
engine in `lua/cyclomatic/analyzer.lua` knows nothing about any language; it
only knows what these capture names mean.

Neovim resolves the file through `vim.treesitter.query.get(lang, 'cyclomatic')`,
which searches the whole runtimepath. A file at
`~/.config/nvim/queries/<lang>/cyclomatic.scm` therefore **replaces** the one
shipped here — that is the supported way to change the rules, and it needs no
configuration.

## Captures

| Capture | Cyclomatic | Cognitive | Deepens nesting |
| --- | --- | --- | --- |
| `@function.body` | starts a new function at 1 | starts at 0 | resets to 0 |
| `@function.name` | — | — | — |
| `@function.signature` | — | — | — |
| `@decision` | +1 | +1 + nesting | yes |
| `@decision.flat` | +1 | one per operator *run* | no |
| `@cyclomatic` | +1 | — | no |
| `@cognitive` | — | +1 + nesting | yes |
| `@cognitive.flat` | — | +1 | no |
| `@chained` | modifier | flattens the increment | yes |
| `@alongside` | modifier | — | reached at the parent's depth |

### Notes on each

**`@function.body`** is required and defines the *range* a function owns.
`@function.name` gives the label and the row the annotation attaches to. When a
grammar has no usable `name:` field — Dart factory constructors have none, named
constructors have two — capture `@function.signature` instead and the label is
derived from its text: everything before the first `(` is kept, then the last
token, with `get`/`set`/`operator` retained as a prefix.

**`@decision`** is the common case: `if`, loops, `catch`, ternaries. It counts
toward both metrics and makes everything inside it one level deeper.

**`@decision.flat`** is for boolean operators. The two metrics genuinely differ
here: cyclomatic complexity charges every operator (`a && b && c` costs 2),
while cognitive complexity charges one point per *run* of the same operator read
left to right (`a && b && c` costs 1, `a || b && c || d` costs 3). Runs are
counted per expression, so two separate `if a && b` cost 1 each.

**`@cyclomatic` and `@cognitive` split a construct.** A `switch` is the clearest
case: cyclomatic complexity charges each `case` and ignores the `switch`, while
cognitive complexity charges the `switch` once and ignores the cases. So the
cases get `@cyclomatic` and the statement gets `@cognitive`.

**`@chained`** marks an `else if`. It is still a branch cyclomatically, but
cognitively it is a continuation, so it takes no nesting penalty of its own —
while its body is still one level deeper than the `if` it hangs off.

**`@alongside`** marks a child that is *beside* a construct rather than inside
it: an `else` branch, or a closure written in an `if` initialiser. Such a node
is visited at the depth its parent was reached at, not the deeper level that
applies to the parent's body.

`default:` clauses are deliberately never captured — they add no independent
path.

## Adding a language

1. Find the node names: `:InspectTree` on a file, or
   `nvim --headless -l tests/tools/dump.lua <file> <lang>`.
2. Write `queries/<lang>/cyclomatic.scm`. Start from `queries/go/cyclomatic.scm`.
3. Add a fixture under `tests/fixtures/<lang>/` with `EXPECT` comments and run
   `nvim --headless -l tests/run.lua`.

Two mistakes are worth knowing about in advance, because both fail *silently*
rather than erroring:

- **Signature and body may be siblings, not parent and child.** In Dart a
  pattern that nests them matches nothing, and every function reports CC=1.
  Anchor them with `.` instead.
- **Operator chains may or may not flatten.** Check whether `a && b && c` is one
  node with two operator children or two nested nodes. Capture whichever node
  occurs once per operator.

;; Cyclomatic / cognitive complexity rules for JavaScript.
;;
;; Two rules that are not obvious from the grammar, both confirmed against
;; ESLint's `complexity` rule -- the same "lower the threshold until
;; everything trips it" trick luacheck is used for on Lua:
;;
;;   * Optional chaining (`?.`) is NOT a branch. `obj?.a?.b?.()` scores the
;;     same as `obj.a.b()`.
;;   * The logical assignment operators `??=`, `||=` and `&&=` ARE branches,
;;     same as `??`, `||` and `&&` -- `a ||= b` runs the assignment only when
;;     `a` is falsy, and ESLint charges a point for each.
;;
;; A function's body is always a *child* of its signature, unlike Dart. But an
;; arrow function's body is not always a block: `(n) => n * 2` and
;; `() => ({ a: 1 })` put an expression directly in that slot, so
;; @function.body is a wildcard there rather than assuming a statement_block.
;;
;; `else` is never a direct child of if_statement, unlike Go and Dart: both a
;; plain `else` and an `else if` sit inside an intermediate else_clause
;; wrapper. The wrapper carries no score of its own -- hence @alongside, not
;; @cognitive.flat -- so it does not silently add a nesting level; the real
;; capture is one level inside it, on whichever of the two shapes is there.
;;
;; Class field initializers and `static {}` blocks are not treated as
;; functions here, though ESLint's `complexity` rule scores each one on its
;; own. No other language in this plugin creates an entry for plain top-level
;; code, and neither does this: any branching inside one is counted at file
;; level instead.

; ---------------------------------------------------------------- functions --
(function_declaration
  name: (_) @function.name
  body: (statement_block) @function.body)

(generator_function_declaration
  name: (_) @function.name
  body: (statement_block) @function.body)

(function_expression
  body: (statement_block) @function.body)
(function_expression
  name: (identifier) @function.name
  body: (statement_block) @function.body)

(generator_function
  body: (statement_block) @function.body)
(generator_function
  name: (identifier) @function.name
  body: (statement_block) @function.body)

; An arrow function's body is a block only when written with braces; every
; other case -- `(n) => n * 2`, `() => ({ a: 1 })`, `async () => await g()` --
; puts an expression directly in the same slot.
(arrow_function
  body: (_) @function.body)

; Class methods, getters, setters, static and private members, and object
; literal shorthand methods (including their getters/setters) are all the
; same node. `name:` holds a property_identifier or, for `#x`, a
; private_property_identifier -- the wildcard reads correctly either way.
(method_definition
  name: (_) @function.name
  body: (statement_block) @function.body)

; A closure bound to a name is labelled with that name instead of <closure>,
; the same convention Go and Lua use for theirs -- covering `const`/`let`
; bindings, plain assignment (`Widget.prototype.f = function () {}`), and
; object-literal properties (`{ onClick: function (e) {} }`).
(variable_declarator
  name: (identifier) @function.name
  value: (function_expression body: (statement_block) @function.body))
(variable_declarator
  name: (identifier) @function.name
  value: (arrow_function body: (_) @function.body))

(assignment_expression
  left: (identifier) @function.name
  right: (function_expression body: (statement_block) @function.body))
(assignment_expression
  left: (identifier) @function.name
  right: (arrow_function body: (_) @function.body))
(assignment_expression
  left: (member_expression property: (property_identifier) @function.name)
  right: (function_expression body: (statement_block) @function.body))
(assignment_expression
  left: (member_expression property: (property_identifier) @function.name)
  right: (arrow_function body: (_) @function.body))

(pair
  key: (property_identifier) @function.name
  value: (function_expression body: (statement_block) @function.body))
(pair
  key: (property_identifier) @function.name
  value: (arrow_function body: (_) @function.body))

; A class field holding an arrow function -- the auto-bound handler idiom
; (`onClick = (e) => { ... }`) -- is named from the field, not left <closure>.
(field_definition
  property: (property_identifier) @function.name
  value: (function_expression body: (statement_block) @function.body))
(field_definition
  property: (property_identifier) @function.name
  value: (arrow_function body: (_) @function.body))

; ------------------------------------------------------------------ branches --
(if_statement) @decision
(if_statement condition: (_) @alongside)

; `else` sits inside an else_clause wrapper whether it is a plain else or an
; `else if`. The wrapper itself is marked @alongside so it adds no nesting
; level on its own; the real capture is one level inside it -- @cognitive.flat
; on a plain block, or @chained on a nested if_statement for "else if". The
; two are structurally exclusive: else_clause has exactly one of the two as
; its immediate child.
(if_statement alternative: (else_clause) @alongside)
(if_statement alternative: (else_clause (statement_block) @cognitive.flat))
(if_statement alternative: (else_clause (if_statement) @chained))

(for_statement) @decision
(for_statement initializer: (_) @alongside)
(for_statement condition: (_) @alongside)

; Covers both `for...of` and `for...in`, which are the same node here,
; distinguished only by the anonymous "of"/"in" token -- and `for await...of`
; too, distinguished only by an anonymous "await" token this query never has
; to look at.
(for_in_statement) @decision
(for_in_statement right: (_) @alongside)

(while_statement) @decision
(while_statement condition: (_) @alongside)

(do_statement) @decision
(do_statement condition: (_) @alongside)

(ternary_expression) @decision

; `finally` is not a branch; each `catch` is, whether or not it binds a
; parameter -- `catch (e)` and a bare `catch { }` both produce a catch_clause.
(catch_clause) @decision

(switch_statement value: (_) @alongside)
; `default:` is deliberately never captured -- it adds no independent path.
; Two case labels stacked to share one body (`case 2: case 3: ...`) are two
; separate switch_case nodes in this grammar, unlike Go's comma-separated
; `case 2, 3:`, and both are counted here -- confirmed against ESLint.
(switch_case) @cyclomatic
(switch_statement) @cognitive

; ---------------------------------------------------------------- operators --
; Matched as anonymous tokens rather than through the `operator:` field, for
; the same portability reason as every other query here.
((binary_expression "&&") @decision.flat)
((binary_expression "||") @decision.flat)
((binary_expression "??") @decision.flat)

((augmented_assignment_expression "??=") @decision.flat)
((augmented_assignment_expression "||=") @decision.flat)
((augmented_assignment_expression "&&=") @decision.flat)

; Optional chaining (`?.`) is deliberately not captured -- see the note above.

; ------------------------------------------------------------------- jumps ---
; Only a *labelled* break/continue breaks the reader's linear flow; a bare one
; stays inside the loop it is written in, already accounted for by that
; loop's own @decision. A bare break/continue has no statement_identifier
; child, so these patterns exclude them on structure alone.
(break_statement (statement_identifier)) @cognitive.flat
(continue_statement (statement_identifier)) @cognitive.flat

;; Cyclomatic / cognitive complexity rules for Go.
;;
;; Capture vocabulary (see doc/CONTRACT.md):
;;   @function.body    scope of a function (required)
;;   @function.name    label + anchor row (optional)
;;   @decision         cyclomatic +1, cognitive +1+nesting, nesting++
;;   @decision.flat    cyclomatic +1, cognitive +1
;;   @cyclomatic       cyclomatic +1 only
;;   @cognitive        cognitive +1+nesting, nesting++
;;   @cognitive.flat   cognitive +1 only
;;   @chained          modifier: demote to flat (else-if)
;;
;; Cyclomatic rules mirror gocyclo exactly: +1 per if / for / case (excluding
;; default) / comm-case / && / ||, starting from a base of 1.

; ---------------------------------------------------------------- functions --
(function_declaration
  name: (identifier) @function.name
  body: (block) @function.body)

(method_declaration
  name: (field_identifier) @function.name
  body: (block) @function.body)

(func_literal
  body: (block) @function.body)

; A closure bound to a name is labelled with that name instead of <closure>.
; These patterns overlap the bare func_literal one above on purpose -- the
; analyzer keeps whichever match carries a name.
(var_spec
  name: (identifier) @function.name
  value: (expression_list (func_literal body: (block) @function.body)))

(short_var_declaration
  left: (expression_list (identifier) @function.name)
  right: (expression_list (func_literal body: (block) @function.body)))

(keyed_element
  key: (literal_element (identifier) @function.name)
  value: (literal_element (func_literal body: (block) @function.body)))

; ------------------------------------------------------------------ branches --
(if_statement) @decision
(if_statement alternative: (block) @cognitive.flat)
(if_statement alternative: (if_statement) @chained)

(for_statement) @decision

; A construct's header is not inside its body: a closure written in an `if`
; initialiser or a loop clause is at the depth of the statement itself, not one
; level deeper. Only matters when such a header contains branching code.
(if_statement initializer: (_) @alongside)
(if_statement condition: (_) @alongside)
(for_statement (for_clause) @alongside)
(for_statement (range_clause) @alongside)
(expression_switch_statement initializer: (_) @alongside)
(expression_switch_statement value: (_) @alongside)

; `default:` is deliberately not counted -- it adds no independent path.
(expression_case) @cyclomatic
(type_case) @cyclomatic
(communication_case) @cyclomatic

; The switch itself carries no cyclomatic weight (its cases do), but it is a
; nesting structure for cognitive complexity.
(expression_switch_statement) @cognitive
(type_switch_statement) @cognitive
(select_statement) @cognitive

; ---------------------------------------------------------------- operators --
; Matched as anonymous children rather than through the `operator:` field.
; Both work here, but whether a grammar exposes that field varies by version,
; and the anonymous form works either way.
((binary_expression "&&") @decision.flat)
((binary_expression "||") @decision.flat)

; ------------------------------------------------------------------- jumps ---
; Only *labelled* jumps break the reader's linear flow; a plain break/continue
; stays inside the loop it is written in. A bare break/continue has no
; label_name child, so these patterns exclude them on structure alone.
(goto_statement) @cognitive.flat
(break_statement (label_name)) @cognitive.flat
(continue_statement (label_name)) @cognitive.flat

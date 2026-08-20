;; Cyclomatic / cognitive complexity rules for Lua.
;;
;; Two things differ from the Go and Dart queries and are worth knowing before
;; editing this file:
;;
;;   * `binary_expression` has no `operator:` field here, so `and`/`or` cannot be
;;     selected the way Go's `&&` is. They are matched as anonymous children
;;     instead, with the capture on the *expression* -- capturing the token
;;     would put each operator in its own sequence and break the cognitive
;;     run-counting.
;;   * `elseif` and `else` are node types of their own rather than a nested
;;     `if_statement`, so @chained has to be layered onto an explicit @decision
;;     instead of arriving from the generic if pattern.

; ---------------------------------------------------------------- functions --
; Covers `function f()`, `function M.f()` and `function M:f()` alike: the name
; field holds an identifier, a dot_index_expression or a method_index_expression,
; and its text reads correctly as a label in all three cases.
(function_declaration
  name: (_) @function.name
  body: (block) @function.body)

(function_definition
  body: (block) @function.body)

; A closure bound to a name is labelled with it rather than <closure>. These
; overlap the bare function_definition pattern on purpose -- the analyzer keeps
; whichever match carries a name.
(assignment_statement
  (variable_list name: (_) @function.name)
  (expression_list value: (function_definition body: (block) @function.body)))

(field
  name: (identifier) @function.name
  value: (function_definition body: (block) @function.body))

; ------------------------------------------------------------------ branches --
(if_statement) @decision

; An `elseif` is a branch like any other, but cognitively a continuation of the
; `if` rather than a new level of nesting -- hence @decision *and* @chained.
(elseif_statement) @decision
(elseif_statement) @chained

; A plain `else` opens no new path, so it costs nothing cyclomatically while
; still costing a flat point to read.
(else_statement) @cognitive.flat

(for_statement) @decision
(while_statement) @decision
(repeat_statement) @decision

; ---------------------------------------------------------------- operators --
; `and`/`or` are Lua's ternary as well as its boolean operators: `a and b or c`
; is the idiom, and counting the operators covers both uses.
((binary_expression "and") @decision.flat)
((binary_expression "or") @decision.flat)

; ------------------------------------------------------------------- jumps ---
(goto_statement) @cognitive.flat

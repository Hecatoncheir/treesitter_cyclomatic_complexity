;; Cyclomatic / cognitive complexity rules for Python.
;;
;; Three of Python's rules are not obvious, and all three are confirmed by
;; radon:
;;
;;   * `else` on a loop or a `try` is a path of its own -- it runs only when the
;;     loop finished without `break`, or no exception was raised. `else` on an
;;     `if` is not, exactly as in every other language here. The grammar gives
;;     both the same node type, so they are told apart by their parent.
;;   * A comprehension is a loop. `[x for x in xs]` costs a point, and each
;;     extra `for` or `if` clause costs another.
;;   * `assert` is a conditional raise, and counts. radon counts it too, with
;;     `--no-assert` to opt out.

; ---------------------------------------------------------------- functions --
(function_definition
  name: (_) @function.name
  body: (block) @function.body)

; A lambda is deliberately *not* a function here. Python restricts it to a
; single expression, so it can never be complex enough to deserve an entry of
; its own, and reporting `<closure> cc=2` for `key=lambda x: x or 0` is noise.
; Its decisions belong to the function that contains it -- which is also what
; radon does, though radon still separates a nested `def`, as this does.

; ------------------------------------------------------------------ branches --
(if_statement) @decision

; `elif` is a branch like any other, but cognitively a continuation of the `if`
; rather than a new level of nesting.
(elif_clause) @decision
(elif_clause) @chained

(if_statement alternative: (else_clause) @cognitive.flat)

(for_statement) @decision
(while_statement) @decision

; The loop and try variants of `else`, which do open a path.
(for_statement alternative: (else_clause) @decision)
(while_statement alternative: (else_clause) @decision)
(try_statement (else_clause) @decision)

(except_clause) @decision

(conditional_expression) @decision
(assert_statement) @decision

; Comprehensions and generator expressions: every clause is a path.
(for_in_clause) @decision
(if_clause) @decision

; `case _:` is the fall-through arm and opens no independent path. Unlike most
; grammars, Python's makes it identifiable: a wildcard pattern has no named
; child, so requiring one excludes it.
((case_clause (case_pattern (_))) @cyclomatic)
(match_statement) @cognitive

; ---------------------------------------------------------------- operators --
; Matched as anonymous children rather than through a field, which works
; whether or not the grammar version exposes one.
((boolean_operator "and") @decision.flat)
((boolean_operator "or") @decision.flat)

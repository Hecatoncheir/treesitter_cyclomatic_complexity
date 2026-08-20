;; Cyclomatic / cognitive complexity rules for Dart.
;;
;; NOTE: in tree-sitter-dart a function's signature and its body are *siblings*,
;; not parent and child, so the patterns below anchor the two with `.` instead
;; of nesting them. Getting this wrong silently yields CC=1 for the whole file.
;;
;; Dart signature nodes expose `name:` inconsistently (factory constructors have
;; no field at all, named constructors have two), so functions are captured via
;; @function.signature and the label is derived from the signature text.

; ---------------------------------------------------------------- functions --
; Top-level functions, and local functions inside a lambda_expression: in both
; cases the signature is immediately followed by its body.
((function_signature) @function.signature
  .
  (function_body) @function.body)

; Class / mixin / extension members: methods, getters, setters, constructors
; and factory constructors all wrap their signature in method_signature.
((method_signature) @function.signature
  .
  (function_body) @function.body)

; Anonymous closures: `(x) { ... }` and `(x) => ...`
(function_expression
  body: (function_expression_body) @function.body)

; ------------------------------------------------------------------ branches --
(if_statement) @decision
(if_statement alternative: (_) @cognitive.flat)
(if_statement alternative: (if_statement) @chained)

(for_statement) @decision
(while_statement) @decision
(do_statement) @decision

(conditional_expression) @decision

; `catch (e)` and `on X catch (e)` both produce a catch_clause. A bare
; `on X { ... }` handler produces no catch_clause at all -- it is `on`, a type
; and a block as plain siblings -- so it is matched on the block, anchored
; directly after the type. The anchor is what keeps `on X catch (e) { }` from
; being counted twice: there a catch_clause sits between the type and block.
(catch_clause) @decision
(try_statement ("on" . (type_identifier) . (block) @decision))

; `default:` adds no independent path, so only real cases are counted.
(switch_statement_case) @cyclomatic
(switch_statement) @cognitive

; Dart 3 pattern switches. The wildcard arm `_ =>` is indistinguishable from a
; real pattern here, so it is counted too -- see doc/CONTRACT.md.
(switch_expression_case) @cyclomatic
(switch_expression) @cognitive

; ---------------------------------------------------------------- operators --
; Chains nest (`a && b && c` -> two nodes), so each operator yields one capture,
; which is what gocyclo-style counting expects.
(logical_and_expression) @decision.flat
(logical_or_expression) @decision.flat
(if_null_expression) @decision.flat

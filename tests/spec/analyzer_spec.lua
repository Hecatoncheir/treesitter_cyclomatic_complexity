local analyzer = require('cyclomatic.analyzer')
local config = require('cyclomatic.config')

local GO_CLOSURE = [[
package main

func outer(n int) int {
	inner := func(x int) int {
		if x > 0 {
			return x
		}
		return 0
	}
	if n > 0 {
		return inner(n)
	}
	return 0
}
]]

-- Guards the failure mode that costs the most time to diagnose: in
-- tree-sitter-dart a signature and its body are siblings, so a query that
-- nests them matches nothing and every function silently reports CC=1.
local DART_METHOD = [[
class Service {
  Future<int> fetch(int id) async {
    if (id < 0) return -1;
    for (var i = 0; i < id; i++) {
      if (i % 2 == 0) continue;
    }
    return id;
  }
}
]]

---@param source string
---@param lang string
---@return table<string, table>
local function by_name(source, lang)
  local result = analyzer.analyze_string(source, lang)
  local out = {}
  for _, entry in ipairs(result and result.entries or {}) do
    out[entry.name] = entry
  end
  return out
end

return {
  ['inline mode folds a closure into the function holding it'] = function(t)
    config.setup({ nested_functions = 'inline' })
    local entries = by_name(GO_CLOSURE, 'go')
    -- base 1 + the closure's `if` + the outer `if`
    t.eq(entries.outer.cyclomatic, 3)
    t.eq(vim.tbl_count(entries), 1, 'the closure is folded in, not reported separately')
  end,

  ['separate mode gives a closure its own entry'] = function(t)
    config.setup({ nested_functions = 'separate' })
    local entries = by_name(GO_CLOSURE, 'go')
    t.eq(entries.outer.cyclomatic, 2, 'the outer function keeps only its own branch')
    t.eq(entries.inner.cyclomatic, 2, 'base 1 plus the closure branch')
    t.truthy(entries.inner.nested, 'the closure is marked as nested')
    t.eq(entries['<closure>'], nil, 'a closure bound to a name is labelled with it')
    t.falsy(entries.outer.nested)
  end,

  ['a Dart method body is found even though it is a sibling of the signature'] = function(t)
    local entries = by_name(DART_METHOD, 'dart')
    t.truthy(entries.fetch, 'the method was not found at all')
    -- base 1 + `if` + `for` + `if`
    t.eq(entries.fetch.cyclomatic, 4, 'CC=1 here means the sibling anchor broke')
  end,

  ['entry_at() returns the innermost function containing a row'] = function(t)
    config.setup({ nested_functions = 'separate' })
    local result = analyzer.analyze_string(GO_CLOSURE, 'go')
    -- row 4 (0-indexed) is the `if x > 0` inside the closure
    local inner = analyzer.entry_at(result, 4)
    t.eq(inner.name, 'inner')
    -- row 10 is the outer `if`, past the closure
    local outer = analyzer.entry_at(result, 10)
    t.eq(outer.name, 'outer')
    t.eq(analyzer.entry_at(result, 0), nil, 'the package clause is in no function')
  end,

  ['entries carry 0-indexed rows spanning the body'] = function(t)
    local result = analyzer.analyze_string(GO_CLOSURE, 'go')
    local outer = result.entries[1]
    t.eq(outer.name, 'outer')
    t.eq(outer.row, 2, 'row is 0-indexed and points at the signature')
    t.truthy(outer.end_row > outer.row, 'end_row covers the body')
  end,

  ['a language without a query is reported, not raised'] = function(t)
    local result, err = analyzer.analyze_string('a: 1', 'yaml')
    t.eq(result, nil)
    t.contains(err, 'yaml')
  end,

  ['an empty source yields no entries'] = function(t)
    local result = analyzer.analyze_string('', 'go')
    t.truthy(result)
    t.eq(result.entries, {})
    t.eq(result.file_level.cyclomatic, 0)
  end,

  ['a file that does not parse cleanly still reports what it can'] = function(t)
    -- Missing closing brace on `broken`. Tree-sitter recovers, and a plugin
    -- that runs on every keystroke has to survive half-typed code.
    local source = [[
package main

func whole(n int) int {
	if n > 0 {
		return 1
	}
	return 0
}

func broken(n int) int {
	if n > 0 {
		return 1
]]
    local result = analyzer.analyze_string(source, 'go')
    t.truthy(result, 'analysis must not fail on unparseable input')
    local names = vim.tbl_map(function(e)
      return e.name
    end, result.entries)
    t.truthy(vim.tbl_contains(names, 'whole'), 'the intact function is still measured')
  end,

  ['Go and Dart agree on the same branching shape'] = function(t)
    local go = by_name(
      'package main\nfunc f(n int, a, b bool) int {\n if n < 0 && a {\n return -1\n } else if n == 0 || b {\n return 0\n } else {\n return 1\n }\n}\n',
      'go'
    )
    local dart = by_name(
      'int f(int n, bool a, bool b) {\n if (n < 0 && a) {\n return -1;\n } else if (n == 0 || b) {\n return 0;\n } else {\n return 1;\n }\n}\n',
      'dart'
    )
    t.eq(go.f.cyclomatic, dart.f.cyclomatic, 'cyclomatic must not depend on the language')
    t.eq(go.f.cognitive, dart.f.cognitive, 'cognitive must not depend on the language')
  end,
}

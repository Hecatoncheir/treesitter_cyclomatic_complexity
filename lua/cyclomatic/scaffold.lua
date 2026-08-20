--- Derives a draft `cyclomatic.scm` by inspecting parsed sample code.
---
--- The hard part of adding a language is never the query syntax -- it is
--- learning the grammar's node names and, worse, noticing the places where its
--- shape differs from the last grammar you looked at. Those differences fail
--- silently: a query written for the wrong shape reports CC=1 for every
--- function without erroring. This module finds them and says so.
---
--- The output is a starting point, not an answer. It is always valid query
--- syntax, so it can be saved and run immediately, but every pattern in it is a
--- guess that wants checking against a reference tool.
local M = {}

--- Word segments suggesting a node's role. Matched against the
--- underscore-separated segments of a type, never as substrings: "identifier"
--- contains "if".
local ROLES = {
  fn = {
    'function',
    'method',
    'lambda',
    'closure',
    'constructor',
    'factory',
    'getter',
    'setter',
    'subroutine',
    'def',
  },
  branch = {
    'if',
    'elif',
    'elseif',
    'unless',
    'for',
    'foreach',
    'while',
    'loop',
    'repeat',
    'do',
    'catch',
    'except',
    'rescue',
    'conditional',
    'ternary',
    'guard',
  },
  switch = { 'switch', 'select', 'match' },
  case = { 'case', 'when', 'arm' },
  -- A fall-through arm adds no independent path in any language, so it is
  -- separated out rather than captured.
  fallthrough = { 'default', 'else', 'otherwise', 'wildcard' },
  operand = { 'binary', 'logical', 'boolean', 'coalesce' },
}

--- Tokens that make a construct a branch rather than arithmetic.
local BOOLEAN_TOKENS = {
  ['&&'] = true,
  ['||'] = true,
  ['and'] = true,
  ['or'] = true,
  ['??'] = true,
  ['and then'] = true,
  ['or else'] = true,
}

--- Suffixes that usually mark a *piece* of a construct rather than the
--- construct itself. `for_clause` in Go is one; Python's `elif_clause` is not,
--- so these are reported for review instead of being dropped or trusted.
local PART_SUFFIX = { '_clause$', '_parts$', '_pattern$', '_list$', '_parameters$', '_declarator$' }

---@param node_type string
---@return table<string, boolean>
local function segments(node_type)
  local out = {}
  for segment in node_type:gmatch('[a-z]+') do
    out[segment] = true
  end
  return out
end

---@param node_type string
---@param role string
---@return boolean
local function has_role(node_type, role)
  local segs = segments(node_type)
  for _, word in ipairs(ROLES[role]) do
    if segs[word] then
      return true
    end
  end
  return false
end

---@param node_type string
---@return boolean
local function looks_like_part(node_type)
  for _, suffix in ipairs(PART_SUFFIX) do
    if node_type:find(suffix) then
      return true
    end
  end
  return false
end

---@param node_type string
---@return boolean
local function looks_like_body(node_type)
  return node_type:find('body') ~= nil
    or node_type:find('block') ~= nil
    or node_type == 'statement_list'
    or node_type == 'suite'
end

---@class CyclomaticScaffoldFindings
---@field functions table<string, table>  type -> { body, sibling_body, name_field, count }
---@field branches table<string, integer>
---@field parts table<string, integer>
---@field switches table<string, integer>
---@field cases table<string, integer>
---@field operators table<string, table>  type -> { form, token }
---@field unclassified table<string, integer>
---@field warnings string[]
---@field sources string[]

--- Inspect one syntax tree, accumulating into `findings`.
---@param root TSNode
---@param source string
---@param findings CyclomaticScaffoldFindings
local function inspect_tree(root, source, findings)
  local function visit(node)
    for child in node:iter_children() do
      if child:named() then
        local node_type = child:type()
        findings.seen[node_type] = (findings.seen[node_type] or 0) + 1
        local classified = false

        -- A body is not a function however it is named (`function_body`), and a
        -- signature nested inside another function candidate is already covered
        -- by the outer one -- Dart wraps function_signature in method_signature.
        -- Walk up only as far as the first body: a signature wrapped by a
        -- larger signature is a duplicate of it, but a closure written *inside*
        -- a function body is a function in its own right, and the body is what
        -- separates the two cases.
        local nested_in_function = false
        local ancestor = child:parent()
        while ancestor do
          local ancestor_type = ancestor:type()
          if looks_like_body(ancestor_type) then
            break
          end
          if has_role(ancestor_type, 'fn') and not looks_like_part(ancestor_type) then
            nested_in_function = true
            break
          end
          ancestor = ancestor:parent()
        end

        if
          has_role(node_type, 'fn')
          and not looks_like_part(node_type)
          and not looks_like_body(node_type)
          and not nested_in_function
          and not node_type:find('call')
        then
          classified = true
          local record = findings.functions[node_type] or { count = 0 }
          record.count = record.count + 1

          local body = child:field('body')[1]
          if body then
            record.body = body:type()
          else
            -- The trap worth the whole module: in some grammars a function's
            -- body is the signature's *sibling*, not its child, and a query
            -- that nests them matches nothing at all.
            local sibling = child:next_named_sibling()
            if sibling and looks_like_body(sibling:type()) then
              record.sibling_body = sibling:type()
            end
          end

          local name = child:field('name')[1]
          record.name_field = name ~= nil
          findings.functions[node_type] = record
        elseif has_role(node_type, 'operand') or node_type:find('if_null') then
          -- How a grammar exposes `&&` decides how the query must select it:
          -- as a field predicate, as an anonymous child, or by capturing the
          -- expression when the operator is a named node.
          local operator = child:field('operator')[1]
          local second = child:child(1)
          if operator and BOOLEAN_TOKENS[operator:type()] then
            classified = true
            findings.operators[node_type] = findings.operators[node_type]
              or { form = 'field', tokens = {} }
            findings.operators[node_type].tokens[operator:type()] = true
          elseif second and not second:named() and BOOLEAN_TOKENS[second:type()] then
            classified = true
            findings.operators[node_type] = findings.operators[node_type]
              or { form = 'anonymous', tokens = {} }
            findings.operators[node_type].tokens[second:type()] = true
          elseif second and second:named() and second:type():find('operator') then
            classified = true
            findings.operators[node_type] =
              { form = 'named', operator_node = second:type(), tokens = {} }
          end
        elseif has_role(node_type, 'switch') then
          classified = true
          findings.switches[node_type] = (findings.switches[node_type] or 0) + 1
        elseif has_role(node_type, 'case') then
          classified = true
          if has_role(node_type, 'fallthrough') then
            findings.fallthrough[node_type] = (findings.fallthrough[node_type] or 0) + 1
          else
            findings.cases[node_type] = (findings.cases[node_type] or 0) + 1
          end
        elseif has_role(node_type, 'branch') then
          classified = true
          if looks_like_part(node_type) then
            findings.parts[node_type] = (findings.parts[node_type] or 0) + 1
          else
            findings.branches[node_type] = (findings.branches[node_type] or 0) + 1
          end
        end

        if not classified then
          findings.unclassified[node_type] = (findings.unclassified[node_type] or 0) + 1
        end

        visit(child)
      end
    end
  end

  local _ = source
  visit(root)
end

--- Inspect sample sources for a language.
---@param sources { name: string, text: string }[]
---@param lang string
---@return CyclomaticScaffoldFindings|nil
---@return string|nil err
function M.inspect(sources, lang)
  local findings = {
    functions = {},
    branches = {},
    parts = {},
    switches = {},
    cases = {},
    fallthrough = {},
    operators = {},
    unclassified = {},
    seen = {},
    warnings = {},
    sources = {},
  }

  for _, sample in ipairs(sources) do
    local ok, parser = pcall(vim.treesitter.get_string_parser, sample.text, lang)
    if not ok or not parser then
      return nil, 'no parser for ' .. lang
    end
    findings.sources[#findings.sources + 1] = sample.name
    inspect_tree(parser:parse()[1]:root(), sample.text, findings)
  end

  return findings
end

---@param map table<string, any>
---@return string[]
local function sorted_keys(map)
  local keys = {}
  for key in pairs(map) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

--- Render findings as a draft query file.
---
--- Everything that is not a pattern is a `;` comment, so the result always
--- parses as a query even where the guesses are wrong.
---@param findings CyclomaticScaffoldFindings
---@param lang string
---@return string
function M.render(findings, lang)
  local out = {}
  local function put(line)
    out[#out + 1] = line or ''
  end

  put(';; Draft queries/' .. lang .. '/cyclomatic.scm')
  put(';; Generated from: ' .. table.concat(findings.sources, ', '))
  put(';;')
  put(';; EVERY PATTERN BELOW IS A GUESS. Check the counts against a reference')
  put(';; tool before trusting them -- see doc/ADDING-A-LANGUAGE.md.')
  put()

  -- ---------------------------------------------------------------- functions
  put('; ------------------------------------------------------------ functions --')
  local fn_types = sorted_keys(findings.functions)
  if #fn_types == 0 then
    put('; NOTHING FOUND. Without a @function.body the metric has nothing to')
    put('; attach to, so this is the first thing to fix.')
  end
  for _, node_type in ipairs(fn_types) do
    local record = findings.functions[node_type]
    if record.sibling_body then
      findings.warnings[#findings.warnings + 1] = string.format(
        '%s keeps its body in a SIBLING (%s), not a child -- nesting them in a '
          .. 'query matches nothing and reports CC=1 everywhere',
        node_type,
        record.sibling_body
      )
      put(('((%s) @function.signature'):format(node_type))
      put('  .')
      put(('  (%s) @function.body)'):format(record.sibling_body))
    elseif record.body then
      put(('(%s'):format(node_type))
      if record.name_field then
        put('  name: (_) @function.name')
      end
      put(('  body: (%s) @function.body)'):format(record.body))
    end
    if record.body or record.sibling_body then
      put()
    end
  end

  -- A candidate with a function-ish name but no body anywhere in the sample is
  -- most likely not a function at all -- Lua's `table_constructor` is one --
  -- so it is listed for review rather than emitted as a pattern.
  local bodyless = {}
  for _, node_type in ipairs(fn_types) do
    local record = findings.functions[node_type]
    if not record.body and not record.sibling_body then
      bodyless[#bodyless + 1] = node_type
    end
  end
  if #bodyless > 0 then
    put('; Named like functions, but no body was found for them in the sample.')
    put('; Most will be something else; any that are real need their shape')
    put('; checked by hand.')
    for _, node_type in ipairs(bodyless) do
      put((';;   %s'):format(node_type))
    end
    put()
  end

  -- ----------------------------------------------------------------- branches
  put('; ------------------------------------------------------------- branches --')
  for _, node_type in ipairs(sorted_keys(findings.branches)) do
    put(('(%s) @decision'):format(node_type))
  end
  put()

  if next(findings.switches) or next(findings.cases) then
    put('; A switch splits between the metrics: its cases carry the cyclomatic')
    put('; weight, the statement itself carries the cognitive nesting.')
    for _, node_type in ipairs(sorted_keys(findings.switches)) do
      put(('(%s) @cognitive'):format(node_type))
    end
    for _, node_type in ipairs(sorted_keys(findings.cases)) do
      put(('(%s) @cyclomatic'):format(node_type))
    end
    for _, node_type in ipairs(sorted_keys(findings.fallthrough)) do
      put((';; (%s) -- left uncaptured on purpose: a fall-through arm opens no'):format(node_type))
      put(';; independent path, so counting it inflates every switch by one.')
    end
    put()
  end

  -- ---------------------------------------------------------------- operators
  put('; ------------------------------------------------------------ operators --')
  local op_types = sorted_keys(findings.operators)
  for _, node_type in ipairs(op_types) do
    local record = findings.operators[node_type]
    if record.form == 'field' or record.form == 'anonymous' then
      -- Always the anonymous form, even where an `operator:` field exists:
      -- whether a grammar exposes that field varies between versions of it,
      -- and matching the token works either way.
      for _, token in ipairs(sorted_keys(record.tokens)) do
        put(('((%s "%s") @decision.flat)'):format(node_type, token))
      end
    else
      put(
        (';; %s carries its operator as a named child (%s). Capture the'):format(
          node_type,
          record.operator_node
        )
      )
      put(';; expression, not the token: capturing tokens puts every operator in')
      put(';; its own sequence and overcharges cognitive complexity.')
      put(('(%s) @decision.flat'):format(node_type))
    end
  end
  put()

  -- ------------------------------------------------------------------- notes
  if #findings.warnings > 0 then
    put('; ==== WOULD OTHERWISE HAVE FAILED SILENTLY ====')
    for _, warning in ipairs(findings.warnings) do
      put('; * ' .. warning)
    end
    put()
  end

  local missing = {}
  if #fn_types == 0 then
    missing[#missing + 1] = 'no functions'
  end
  if not next(findings.branches) then
    missing[#missing + 1] = 'no if/loop constructs'
  end
  if #op_types == 0 then
    missing[#missing + 1] = 'no boolean operators (`a && b`)'
  end
  if not next(findings.switches) and not next(findings.cases) then
    missing[#missing + 1] = 'no switch/match'
  end
  if #missing > 0 then
    put('; ==== NOT PRESENT IN THE SAMPLE ====')
    put('; A rule cannot be guessed from code that does not use it. If ' .. lang .. ' has')
    put('; these, extend the sample and run this again:')
    for _, item in ipairs(missing) do
      put('; * ' .. item)
    end
    put()
  end

  if next(findings.parts) then
    put('; ==== PROBABLY PARTS, BUT CHECK ====')
    put('; These name a piece of a construct in most grammars -- but not all:')
    put("; Python's elif_clause is a real branch. Uncomment what belongs.")
    for _, node_type in ipairs(sorted_keys(findings.parts)) do
      put((';; (%s) @decision'):format(node_type))
    end
    put()
  end

  local candidates = {}
  for _, node_type in ipairs(sorted_keys(findings.unclassified)) do
    if
      findings.seen[node_type]
      and not node_type:find('identifier')
      and not node_type:find('literal')
    then
      candidates[#candidates + 1] = { node_type, findings.unclassified[node_type] }
    end
  end
  table.sort(candidates, function(a, b)
    return a[2] > b[2]
  end)
  if #candidates > 0 then
    put('; ==== SEEN BUT NOT CLASSIFIED ====')
    put('; Scan these for anything that branches and the heuristics missed.')
    local shown = math.min(#candidates, 25)
    for index = 1, shown do
      put((';   %-34s x%d'):format(candidates[index][1], candidates[index][2]))
    end
    if #candidates > shown then
      put((';   ... and %d more'):format(#candidates - shown))
    end
  end

  return table.concat(out, '\n') .. '\n'
end

--- Inspect sources and render a draft in one call.
---@param sources { name: string, text: string }[]
---@param lang string
---@return string|nil draft
---@return string|nil err
function M.generate(sources, lang)
  local findings, err = M.inspect(sources, lang)
  if not findings then
    return nil, err
  end
  return M.render(findings, lang)
end

--- Read files from disk and render a draft.
---@param paths string[]
---@param lang string
---@return string|nil draft
---@return string|nil err
function M.from_files(paths, lang)
  local sources = {}
  for _, path in ipairs(paths) do
    local handle = io.open(path, 'r')
    if not handle then
      return nil, 'cannot read ' .. path
    end
    sources[#sources + 1] = { name = path:match('[^/]+$'), text = handle:read('*a') }
    handle:close()
  end
  return M.generate(sources, lang)
end

return M

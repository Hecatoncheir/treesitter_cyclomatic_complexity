--- Core metric engine.
---
--- Everything language-specific lives in `queries/<lang>/cyclomatic.scm`; this
--- module only knows what the capture names mean. See doc/CONTRACT.md.
local config = require('cyclomatic.config')

local M = {}

--- What each capture contributes.
---   cyc  -- cyclomatic increment
---   cog  -- cognitive increment (before the nesting penalty)
---   nest -- whether descendants are one level deeper for cognitive purposes
---   pen  -- whether the cognitive increment takes the nesting penalty
local SEMANTICS = {
  ['decision'] = { cyc = 1, cog = 1, nest = true, pen = true },
  ['decision.flat'] = { cyc = 1, cog = 1, nest = false, pen = false, seq = true },
  ['cyclomatic'] = { cyc = 1, cog = 0, nest = false, pen = false },
  ['cognitive'] = { cyc = 0, cog = 1, nest = true, pen = true },
  ['cognitive.flat'] = { cyc = 0, cog = 1, nest = false, pen = false },
  ['nesting'] = { cyc = 0, cog = 0, nest = true, pen = false },
}

local QUERY_NAME = 'cyclomatic'

--- Lookup results per language, so repeated lookups on unsupported buffers stay
--- cheap. The failure reason is cached alongside: a missing query and a parser
--- whose ABI the running Neovim cannot load are very different problems, and
--- only one of them is the user's to fix.
---@type table<string, { query: vim.treesitter.Query|nil, err: string|nil }>
local query_cache = {}

--- Fetch the complexity query for a language.
---@param lang string
---@return vim.treesitter.Query|nil query
---@return string|nil err
function M.get_query(lang)
  local cached = query_cache[lang]
  if cached then
    return cached.query, cached.err
  end

  local ok, result = pcall(vim.treesitter.query.get, lang, QUERY_NAME)
  local entry
  if not ok then
    entry = { err = tostring(result) }
  elseif not result then
    entry = { err = 'no ' .. QUERY_NAME .. ' query for ' .. lang }
  else
    entry = { query = result }
  end

  query_cache[lang] = entry
  return entry.query, entry.err
end

--- Drop cached queries so edited .scm files are picked up without a restart.
function M.reload()
  query_cache = {}
  if vim.treesitter.query.invalidate_query_cache then
    vim.treesitter.query.invalidate_query_cache()
  end
end

--- Every language with a complexity query anywhere on the runtimepath.
---
--- Found by glob rather than from a hard-coded list, so a query dropped into a
--- user's own config directory counts as support.
---@return string[]
function M.languages()
  local found = {}
  for _, path in ipairs(vim.api.nvim_get_runtime_file('queries/*/' .. QUERY_NAME .. '.scm', true)) do
    local lang = path:match('queries/([^/]+)/')
    if lang then
      found[lang] = true
    end
  end
  local out = vim.tbl_keys(found)
  table.sort(out)
  return out
end

--- Resolve the tree-sitter language for a buffer.
---@param bufnr integer
---@return string|nil
function M.buf_lang(bufnr)
  local ft = vim.bo[bufnr].filetype
  if ft == '' then
    return nil
  end
  return vim.treesitter.language.get_lang(ft) or ft
end

--- Turn a signature's text into a readable label.
---
--- Generic rule: drop everything from the first `(` (parameter list and any
--- trailing initialiser list), then keep the last token -- which is the name in
--- every C-family signature shape. `get`/`set`/`operator` are kept as a prefix
--- because on their own the bare name would be ambiguous.
---@param text string
---@return string|nil
local function derive_name(text)
  local head = (text:match('^[^(]*') or text):gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
  local tokens = vim.split(head, ' ', { trimempty = true })
  if #tokens == 0 then
    return nil
  end
  local last, prev = tokens[#tokens], tokens[#tokens - 1]
  if prev == 'get' or prev == 'set' or prev == 'operator' then
    return prev .. ' ' .. last
  end
  return last
end

--- Locate the token carrying a binary operator, so operator sequences can be
--- ordered by position in the source rather than by depth in the tree.
---@param node TSNode
---@return TSNode|nil
local function operator_token(node)
  local field = node:field('operator')[1]
  if field then
    return field
  end
  -- Grammars without an `operator` field (Dart among them) put the token
  -- second, either anonymous (`??`) or as a named `*_operator` node.
  local second = node:child(1)
  if second and (not second:named() or second:type():find('operator', 1, true)) then
    return second
  end
  return nil
end

--- Note a logical operator against the frame that owns it. `group` is the
--- expression the operator belongs to; runs are counted per expression, never
--- across the function as a whole.
---@param frame table
---@param node TSNode
---@param group string
local function record_operator(frame, node, group)
  local token = operator_token(node)
  local anchor = token or node
  local row, col = anchor:start()
  frame.ops[#frame.ops + 1] = {
    row = row,
    col = col,
    id = token and token:type() or node:type(),
    group = group,
  }
end

--- Cognitive complexity charges one point per *run* of the same logical
--- operator read left to right within one expression: `a && b && c` costs 1,
--- `a || b && c || d` costs 3, and two separate `if a && b` cost 1 each.
--- Cyclomatic complexity instead charges every operator, which is why the two
--- are accumulated separately.
---@param ops table[]
---@return integer
local function sequence_cost(ops)
  local groups, order = {}, {}
  for _, op in ipairs(ops) do
    if not groups[op.group] then
      groups[op.group] = {}
      order[#order + 1] = op.group
    end
    table.insert(groups[op.group], op)
  end

  local total, starts = 0, {}
  for _, key in ipairs(order) do
    local group = groups[key]
    table.sort(group, function(x, y)
      if x.row ~= y.row then
        return x.row < y.row
      end
      return x.col < y.col
    end)
    local previous
    for _, op in ipairs(group) do
      if op.id ~= previous then
        total = total + 1
        -- Which operator opened each run, so `explain` can say why
        -- `a and b and c` costs two cyclomatically but one cognitively.
        starts[#starts + 1] = op
        previous = op.id
      end
    end
  end
  return total, starts
end

--- Collect capture information for one syntax tree.
---@param query vim.treesitter.Query
---@param root TSNode
---@param source integer|string
---@return table<string, table<string, boolean>> marks  node id -> capture set
---@return table<string, table> bodies                  body node id -> {name, sig}
local function collect(query, root, source)
  local marks, bodies = {}, {}

  -- One pass over the matches collects both halves: which nodes start a
  -- function, and what every other captured node contributes. Splitting this
  -- into iter_matches + iter_captures runs the query twice for no benefit.
  for _, match in query:iter_matches(root, source, 0, -1) do
    local body, name_node, sig_node
    for id, nodes in pairs(match) do
      local capture = query.captures[id]
      local list = type(nodes) == 'table' and nodes or { nodes }
      for _, node in ipairs(list) do
        if capture == 'function.body' then
          body = node
        elseif capture == 'function.name' then
          name_node = node
        elseif capture == 'function.signature' then
          sig_node = node
        elseif SEMANTICS[capture] or capture == 'chained' or capture == 'alongside' then
          local key = node:id()
          marks[key] = marks[key] or {}
          marks[key][capture] = true
        end
      end
    end
    if body then
      -- Several patterns may match the same body (a bare closure and the
      -- binding that names it). Keep whichever one actually identifies it, so
      -- the result does not depend on pattern order.
      local key = body:id()
      local prev = bodies[key]
      if not prev or (not (prev.name or prev.signature) and (name_node or sig_node)) then
        bodies[key] = { name = name_node, signature = sig_node }
      end
    end
  end

  return marks, bodies
end

--- Build the display label and anchor position for a function.
---@param body TSNode
---@param meta table
---@param source integer|string
---@return string name
---@return integer row  0-indexed anchor row for annotations
local function label_of(body, meta, source)
  if meta.name then
    return vim.treesitter.get_node_text(meta.name, source), meta.name:start()
  end
  if meta.signature then
    local text = vim.treesitter.get_node_text(meta.signature, source)
    local derived = derive_name(text)
    if derived then
      return derived, meta.signature:start()
    end
  end
  return '<closure>', body:start()
end

---@class CyclomaticEntry
---@field name string
---@field row integer          0-indexed row the annotation attaches to
---@field end_row integer      0-indexed last row of the body
---@field cyclomatic integer
---@field cognitive integer
---@field nested boolean       true when this entry is a closure reported on its own

--- Compute complexity for every function in a syntax tree.
---@param query vim.treesitter.Query
---@param root TSNode
---@param source integer|string
---@return CyclomaticEntry[] entries
---@return table file_level
--- @param frame table
--- @param node TSNode
--- @param capture string
--- @param cyc integer
--- @param cog integer|nil nil while an operator's cognitive cost is undecided
--- @param nesting integer
local function trace(frame, node, capture, cyc, cog, nesting)
  if not frame.contributions then
    return
  end
  local row, col = node:start()
  frame.contributions[#frame.contributions + 1] = {
    row = row,
    col = col,
    node_type = node:type(),
    capture = capture,
    cyclomatic = cyc,
    cognitive = cog,
    nesting = nesting,
  }
end

--- @param query vim.treesitter.Query
--- @param root TSNode
--- @param source integer|string
--- @param tracing boolean|nil record what each point contributed, for `explain`
local function walk_tree(query, root, source, tracing)
  local marks, bodies = collect(query, root, source)
  local separate = config.options.nested_functions == 'separate'

  --- Does this node take part in a logical-operator chain?
  ---@param node TSNode
  ---@return boolean
  local function is_sequence(node)
    local caps = marks[node:id()]
    if not caps then
      return false
    end
    for capture in pairs(caps) do
      local sem = SEMANTICS[capture]
      if sem and sem.seq then
        return true
      end
    end
    return false
  end

  --- Outermost node of a chain of logical operators, used to keep runs from
  --- one expression from merging with runs from another.
  ---@param node TSNode
  ---@return string
  local function sequence_root(node)
    local outermost, parent = node, node:parent()
    while parent and is_sequence(parent) do
      outermost, parent = parent, parent:parent()
    end
    return outermost:id()
  end

  local entries = {}
  local file_level = {
    cyclomatic = 0,
    cognitive = 0,
    ops = {},
    contributions = tracing and {} or nil,
  }

  --- @param node TSNode
  --- @param frame table|nil  the function currently accumulating
  --- @param nesting integer  cognitive nesting depth inside `frame`
  local function visit(node, frame, nesting)
    local caps = marks[node:id()]
    local body_meta = bodies[node:id()]

    if body_meta then
      if frame == nil or separate then
        local name, row = label_of(node, body_meta, source)
        frame = {
          name = name,
          row = row,
          end_row = node:end_(),
          cyclomatic = 1,
          cognitive = 0,
          nested = frame ~= nil,
          ops = {},
          contributions = tracing and {} or nil,
        }
        entries[#entries + 1] = frame
        nesting = 0
        if frame.contributions then
          -- Against the signature row, not the body's first statement: that is
          -- the line the reader associates with the function.
          frame.contributions[1] = {
            row = frame.row,
            col = 0,
            node_type = node:type(),
            capture = 'function.body',
            cyclomatic = 1,
            cognitive = 0,
            nesting = 0,
          }
        end
      else
        -- Inlined into the enclosing function: its branches keep counting
        -- toward `frame`, but they sit one level deeper.
        nesting = nesting + 1
      end
    end

    -- Depth this node was reached at, before its own captures deepen it.
    local inherited = nesting

    if caps then
      local chained = caps['chained']
      -- A node deepens the nesting by at most one level however many captures
      -- it carries, and every capture is scored against the depth the node was
      -- reached at. Applying the increment after the loop keeps the result
      -- independent of the order pairs() happens to yield.
      local deepens = false
      for capture in pairs(caps) do
        local sem = SEMANTICS[capture]
        if sem then
          -- `chained` marks an `else if`: cyclomatically a branch like any
          -- other, but cognitively a continuation, so it is flattened and its
          -- own `cognitive.flat` capture (the generic `else`) is dropped.
          local skip = chained and capture == 'cognitive.flat'
          local flat = chained or not sem.pen
          local target = frame or file_level

          if not skip then
            target.cyclomatic = target.cyclomatic + sem.cyc

            if sem.seq then
              -- Deferred: the cognitive cost of operators depends on how they
              -- group into runs, which is only knowable once all of them are in.
              record_operator(target, node, sequence_root(node))
              trace(target, node, capture, sem.cyc, nil, nesting)
            elseif sem.cog > 0 then
              local cog = sem.cog + (flat and 0 or nesting)
              target.cognitive = target.cognitive + cog
              trace(target, node, capture, sem.cyc, cog, nesting)
            else
              trace(target, node, capture, sem.cyc, 0, nesting)
            end
          end

          -- `chained` flattens the increment for the `else if` itself, but its
          -- own body is still one level deeper than the `if` it hangs off.
          if sem.nest then
            deepens = true
          end
        end
      end
      if deepens then
        nesting = nesting + 1
      end
    end

    for child in node:iter_children() do
      -- An `else` branch sits alongside its `if`, not inside it, so it is
      -- visited at the depth the `if` itself was reached at rather than the
      -- deeper level that applies to the `if`'s own body.
      local child_caps = marks[child:id()]
      local alongside = child_caps
        and (child_caps['chained'] or child_caps['cognitive.flat'] or child_caps['alongside'])
      visit(child, frame, alongside and inherited or nesting)
    end
  end

  visit(root, nil, 0)

  --- @param target table
  local function finalize(target)
    local cost, starts = sequence_cost(target.ops)
    target.cognitive = target.cognitive + cost
    if target.contributions then
      for _, op in ipairs(starts) do
        target.contributions[#target.contributions + 1] = {
          row = op.row,
          col = op.col,
          node_type = op.id,
          capture = 'operator run',
          cyclomatic = 0,
          cognitive = 1,
          nesting = 0,
        }
      end
      -- Source order, so the account reads the way the code does.
      table.sort(target.contributions, function(a, b)
        if a.row ~= b.row then
          return a.row < b.row
        end
        return (a.col or 0) < (b.col or 0)
      end)
    end
    target.ops = nil
  end

  for _, frame in ipairs(entries) do
    finalize(frame)
  end
  finalize(file_level)

  return entries, file_level
end

---@class CyclomaticResult
---@field lang string
---@field entries CyclomaticEntry[]
---@field file_level table

--- Analyze a buffer.
---@param bufnr integer
---@param opts { trace: boolean }|nil record what each point contributed
---@return CyclomaticResult|nil
---@return string|nil err
function M.analyze(bufnr, opts)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return nil, 'buffer not loaded'
  end

  local lang = M.buf_lang(bufnr)
  if not lang then
    return nil, 'no language for buffer'
  end

  local query, err = M.get_query(lang)
  if not query then
    return nil, err or ('no cyclomatic query for ' .. lang)
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok or not parser then
    return nil, 'no parser for ' .. lang
  end

  local entries, file_level = {}, { cyclomatic = 0, cognitive = 0 }
  for _, tree in ipairs(parser:parse() or {}) do
    local got, file = walk_tree(query, tree:root(), bufnr, opts and opts.trace)
    vim.list_extend(entries, got)
    file_level.cyclomatic = file_level.cyclomatic + file.cyclomatic
    file_level.cognitive = file_level.cognitive + file.cognitive
  end

  table.sort(entries, function(a, b)
    if a.row ~= b.row then
      return a.row < b.row
    end
    return a.name < b.name
  end)

  return { lang = lang, entries = entries, file_level = file_level }
end

--- Analyze a string. Used by the project-wide scan, which never opens buffers.
---@param source string
---@param lang string
---@param opts { trace: boolean }|nil record what each point contributed
---@return CyclomaticResult|nil
---@return string|nil err
function M.analyze_string(source, lang, opts)
  local query, err = M.get_query(lang)
  if not query then
    return nil, err or ('no cyclomatic query for ' .. lang)
  end
  local ok, parser = pcall(vim.treesitter.get_string_parser, source, lang)
  if not ok or not parser then
    return nil, 'no parser for ' .. lang
  end
  local entries, file_level =
    walk_tree(query, parser:parse()[1]:root(), source, opts and opts.trace)
  table.sort(entries, function(a, b)
    return a.row < b.row
  end)
  return { lang = lang, entries = entries, file_level = file_level }
end

--- Analyze a buffer with tracing on and return the entry containing `row`,
--- together with the record of what each decision point contributed.
---
--- Separate from analyze() because tracing costs work on every node, and the
--- normal path runs on every keystroke.
---@param bufnr integer
---@param row integer 0-indexed
---@return CyclomaticEntry|nil entry with a `contributions` list
---@return string|nil err
function M.explain(bufnr, row)
  local result, err = M.analyze(bufnr, { trace = true })
  if not result then
    return nil, err
  end
  local entry = M.entry_at(result, row)
  if not entry then
    return nil, 'no function at this line'
  end
  return entry
end

--- The entry whose body contains `row`, innermost first.
---@param result CyclomaticResult|nil
---@param row integer 0-indexed
---@return CyclomaticEntry|nil
function M.entry_at(result, row)
  if not result then
    return nil
  end
  local best
  for _, e in ipairs(result.entries) do
    if row >= e.row and row <= e.end_row then
      if not best or (e.row >= best.row and e.end_row <= best.end_row) then
        best = e
      end
    end
  end
  return best
end

return M

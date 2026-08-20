--- The reuse cache is the one optimisation here that can be silently wrong: a
--- stale entry produces a plausible number rather than an error. Every case
--- below therefore compares the incremental answer against a cold one computed
--- from scratch, rather than against an expected constant.
local analyzer = require('cyclomatic.analyzer')
local config = require('cyclomatic.config')

local SOURCE = table.concat({
  'package main',
  '',
  'func alpha(n int) int {',
  '\tif n > 0 {',
  '\t\treturn 1',
  '\t}',
  '\treturn 0',
  '}',
  '',
  'func beta(a, b bool) int {',
  '\tif a && b {',
  '\t\treturn 1',
  '\t}',
  '\treturn 0',
  '}',
  '',
  'func gamma(xs []int) int {',
  '\tfor _, x := range xs {',
  '\t\tif x > 0 {',
  '\t\t\treturn x',
  '\t\t}',
  '\t}',
  '\treturn 0',
  '}',
}, '\n')

---@param bufnr integer
---@return table[] comparable snapshot of every entry
local function snapshot(bufnr)
  local result = analyzer.analyze(bufnr)
  local out = {}
  for index, entry in ipairs(result.entries) do
    out[index] = {
      name = entry.name,
      row = entry.row,
      end_row = entry.end_row,
      cyclomatic = entry.cyclomatic,
      cognitive = entry.cognitive,
    }
  end
  return out
end

--- The same, with the cache dropped first, so nothing is carried over.
---@param bufnr integer
---@return table[]
local function cold(bufnr)
  analyzer.forget(bufnr)
  return snapshot(bufnr)
end

---@param helpers table
---@param bufnr integer
---@param what string
local function must_agree(helpers, bufnr, what)
  local incremental = snapshot(bufnr)
  local fresh = cold(bufnr)
  helpers.eq(incremental, fresh, what)
end

return {
  ['reuse agrees with a cold analysis through a sequence of edits'] = function(t)
    local bufnr = t.buffer('go', SOURCE)
    must_agree(t, bufnr, 'before any edit')

    -- Rows shift but no subtree changes: the hardest case for the cache, since
    -- tree-sitter reports almost nothing as dirty.
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { '// a comment' })
    must_agree(t, bufnr, 'after inserting a line at the top')

    -- A change confined to one function.
    vim.api.nvim_buf_set_lines(bufnr, 4, 5, false, { '\t\tif n > 1 { return 2 }' })
    must_agree(t, bufnr, 'after editing inside alpha')

    -- A change that alters a function's own complexity.
    vim.api.nvim_buf_set_lines(bufnr, 11, 12, false, { '\tif a && b || !a {' })
    must_agree(t, bufnr, 'after changing an operator chain')

    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, {})
    must_agree(t, bufnr, 'after deleting the inserted line')

    -- A whole new function, which no cached id covers.
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, {
      '',
      'func delta(n int) int {',
      '\tswitch n {',
      '\tcase 1:',
      '\t\treturn 1',
      '\tcase 2:',
      '\t\treturn 2',
      '\t}',
      '\treturn 0',
      '}',
    })
    must_agree(t, bufnr, 'after appending a function')

    -- And removing one.
    local count = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, count - 10, count, false, {})
    must_agree(t, bufnr, 'after removing it again')
  end,

  ['reuse agrees in separate mode too'] = function(t)
    config.setup({ nested_functions = 'separate' })
    local bufnr = t.buffer(
      'go',
      table.concat({
        'package main',
        '',
        'func outer(n int) int {',
        '\tinner := func(x int) int {',
        '\t\tif x > 0 { return x }',
        '\t\treturn 0',
        '\t}',
        '\treturn inner(n)',
        '}',
      }, '\n')
    )
    must_agree(t, bufnr, 'before')
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { '// shift everything' })
    must_agree(t, bufnr, 'after a pure shift, with a nested entry to rebase')
    vim.api.nvim_buf_set_lines(bufnr, 5, 6, false, { '\t\tif x > 0 { if x > 1 { return 2 } }' })
    must_agree(t, bufnr, 'after editing inside the closure')
  end,

  ['switching nesting mode drops what was cached under the other'] = function(t)
    local bufnr = t.buffer('go', SOURCE)
    config.setup({ nested_functions = 'inline' })
    local inline = snapshot(bufnr)
    config.setup({ nested_functions = 'separate' })
    local separate = snapshot(bufnr)
    t.eq(separate, cold(bufnr), 'the inline cache must not leak into separate mode')
    t.truthy(#inline > 0)
  end,

  ['a changed query invalidates every cached number'] = function(t)
    local bufnr = t.buffer('go', SOURCE)
    snapshot(bufnr)
    analyzer.reload()
    t.eq(snapshot(bufnr), cold(bufnr), 'reload must not leave stale entries behind')
  end,

  ['tracing takes the slow path and still agrees'] = function(t)
    local bufnr = t.buffer('go', SOURCE)
    snapshot(bufnr)
    local entry = analyzer.explain(bufnr, 3)
    t.truthy(entry)
    local fresh = cold(bufnr)
    t.eq(entry.cyclomatic, fresh[1].cyclomatic)
    t.eq(entry.cognitive, fresh[1].cognitive)
  end,
}

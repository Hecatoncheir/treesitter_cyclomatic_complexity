local analyzer = require('cyclomatic.analyzer')
local config = require('cyclomatic.config')
local diagnostics = require('cyclomatic.diagnostics')

local SOURCE = table.concat({
  'package main',
  '',
  'func trivial() int { return 1 }',
  '',
  -- Six branches puts `moderate` at cc=7, inside the medium bucket rather
  -- than below the `low` threshold of 5.
  'func moderate(n int) int {',
  '\tif n == 1 { return 1 }',
  '\tif n == 2 { return 2 }',
  '\tif n == 3 { return 3 }',
  '\tif n == 4 { return 4 }',
  '\tif n == 5 { return 5 }',
  '\tif n == 6 { return 6 }',
  '\treturn 0',
  '}',
  '',
  'func awful(n int) int {',
}, '\n')

--- `awful` gets 24 branches appended, putting it in the worst bucket.
local function source_with_awful()
  local lines = { SOURCE }
  for i = 1, 24 do
    lines[#lines + 1] = ('\tif n == %d {\n\t\treturn %d\n\t}'):format(i, i)
  end
  lines[#lines + 1] = '\treturn 0'
  lines[#lines + 1] = '}'
  return table.concat(lines, '\n')
end

---@param bufnr integer
---@return vim.Diagnostic[]
local function publish(bufnr)
  diagnostics.publish(bufnr, analyzer.analyze(bufnr))
  return vim.diagnostic.get(bufnr, { namespace = diagnostics.ns })
end

return {
  ['nothing is published while diagnostics are off'] = function(t)
    local bufnr = t.buffer('go', source_with_awful())
    config.setup({})
    t.falsy(config.options.diagnostics.enabled, 'off by default')
    t.eq(#publish(bufnr), 0)
  end,

  ['enabling publishes the functions above the floor'] = function(t)
    local bufnr = t.buffer('go', source_with_awful())
    config.setup({ diagnostics = { enabled = true, min_complexity = 11 } })
    local items = publish(bufnr)
    t.eq(#items, 1, 'only `awful` clears a floor of 11')
    t.contains(items[1].message, 'awful')
    t.contains(items[1].message, '25')
  end,

  ['the floor is what decides how much is reported'] = function(t)
    local bufnr = t.buffer('go', source_with_awful())
    config.setup({ diagnostics = { enabled = true, min_complexity = 1 } })
    t.eq(#publish(bufnr), 3, 'trivial, moderate and awful')
  end,

  ['severity follows the threshold bucket'] = function(t)
    local bufnr = t.buffer('go', source_with_awful())
    config.setup({ diagnostics = { enabled = true, min_complexity = 1 } })
    local by_name = {}
    for _, item in ipairs(publish(bufnr)) do
      by_name[item.message:match('^(%S+):')] = item.severity
    end
    t.eq(by_name.trivial, vim.diagnostic.severity.HINT)
    t.eq(by_name.moderate, vim.diagnostic.severity.INFO)
    t.eq(by_name.awful, vim.diagnostic.severity.ERROR)
  end,

  ['diagnostics span the function body'] = function(t)
    local bufnr = t.buffer('go', source_with_awful())
    config.setup({ diagnostics = { enabled = true, min_complexity = 1 } })
    for _, item in ipairs(publish(bufnr)) do
      t.truthy(item.end_lnum >= item.lnum, item.message .. ' has a backwards range')
      t.truthy(
        item.end_lnum < vim.api.nvim_buf_line_count(bufnr),
        item.message .. ' runs past the end of the buffer'
      )
    end
  end,

  ['turning diagnostics off clears what was already published'] = function(t)
    local bufnr = t.buffer('go', source_with_awful())
    config.setup({ diagnostics = { enabled = true, min_complexity = 1 } })
    t.truthy(#publish(bufnr) > 0)
    config.setup({ diagnostics = { enabled = false } })
    t.eq(#publish(bufnr), 0)
  end,

  ['the metric in use is named in the message'] = function(t)
    local bufnr = t.buffer('go', source_with_awful())
    config.setup({ metric = 'cognitive', diagnostics = { enabled = true, min_complexity = 1 } })
    local items = publish(bufnr)
    t.truthy(#items > 0)
    t.contains(items[1].message, 'cognitive')
  end,
}

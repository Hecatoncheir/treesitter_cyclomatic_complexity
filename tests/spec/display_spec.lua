local analyzer = require('cyclomatic.analyzer')
local config = require('cyclomatic.config')
local display = require('cyclomatic.display')

--- A Go function whose cyclomatic complexity is `branches + 1`.
---@param name string
---@param branches integer
---@return string
local function go_func(name, branches)
  local lines = { ('func %s(n int) int {'):format(name) }
  for i = 1, branches do
    lines[#lines + 1] = ('\tif n == %d {\n\t\treturn %d\n\t}'):format(i, i)
  end
  lines[#lines + 1] = '\treturn 0'
  lines[#lines + 1] = '}'
  return table.concat(lines, '\n')
end

--- Buffer holding one function per bucket: cc 1, 6, 12 and 25.
---@param helpers table
---@return integer bufnr
local function bucket_buffer(helpers)
  local source = table.concat({
    'package main',
    '',
    go_func('trivial', 0),
    '',
    go_func('moderate', 5),
    '',
    go_func('complex', 11),
    '',
    go_func('awful', 24),
  }, '\n')
  return helpers.buffer('go', source)
end

---@param bufnr integer
local function draw(bufnr)
  display.render(bufnr, analyzer.analyze(bufnr))
end

return {
  ['min_complexity keeps trivial functions unannotated'] = function(t)
    local bufnr = bucket_buffer(t)
    config.setup({ virtual_text = { min_complexity = 4 } })
    draw(bufnr)
    local drawn = table.concat(t.annotations(bufnr), ' ')
    t.contains(drawn, 'CC 6')
    t.contains(drawn, 'CC 12')
    t.contains(drawn, 'CC 25')
    t.falsy(drawn:find('CC 1 '), 'the cc=1 function should be left alone')
  end,

  ['min_complexity = 1 annotates everything'] = function(t)
    local bufnr = bucket_buffer(t)
    config.setup({ virtual_text = { min_complexity = 1 } })
    draw(bufnr)
    t.eq(#t.annotations(bufnr), 4)
  end,

  ['each bucket gets its own highlight group'] = function(t)
    local bufnr = bucket_buffer(t)
    config.setup({ virtual_text = { min_complexity = 1 } })
    draw(bufnr)
    local groups = {}
    for _, group in pairs(t.annotation_highlights(bufnr)) do
      groups[#groups + 1] = group
    end
    table.sort(groups)
    t.eq(groups, {
      'CyclomaticHigh',
      'CyclomaticLow',
      'CyclomaticMedium',
      'CyclomaticVeryHigh',
    })
  end,

  ['thresholds move which group a score lands in'] = function(t)
    local bufnr = bucket_buffer(t)
    config.setup({
      virtual_text = { min_complexity = 1 },
      thresholds = { low = 1, medium = 2, high = 3 },
    })
    draw(bufnr)
    local groups = vim.tbl_values(t.annotation_highlights(bufnr))
    local very_high = #vim.tbl_filter(function(g)
      return g == 'CyclomaticVeryHigh'
    end, groups)
    t.eq(very_high, 3, 'everything above 3 is now the worst bucket')
  end,

  ['disabling virtual text draws nothing'] = function(t)
    local bufnr = bucket_buffer(t)
    config.setup({ virtual_text = { enabled = false, min_complexity = 1 } })
    draw(bufnr)
    t.eq(t.annotations(bufnr), {})
  end,

  ['clear() removes the annotations'] = function(t)
    local bufnr = bucket_buffer(t)
    config.setup({ virtual_text = { min_complexity = 1 } })
    draw(bufnr)
    t.truthy(#t.annotations(bufnr) > 0)
    display.clear(bufnr)
    t.eq(t.annotations(bufnr), {})
  end,

  ['a custom format function controls the text'] = function(t)
    local bufnr = bucket_buffer(t)
    config.setup({
      virtual_text = {
        min_complexity = 1,
        format = function(entry)
          return '<' .. entry.name .. '=' .. entry.cyclomatic .. '>'
        end,
      },
    })
    draw(bufnr)
    t.contains(table.concat(t.annotations(bufnr), ' '), '<awful=25>')
  end,

  ['a format function that errors does not break the render'] = function(t)
    local bufnr = bucket_buffer(t)
    config.setup({
      virtual_text = {
        min_complexity = 1,
        format = function()
          error('boom')
        end,
      },
    })
    draw(bufnr)
    t.eq(t.annotations(bufnr), {}, 'a broken formatter is skipped, not raised')
  end,

  ['switching the metric changes both the label and the value'] = function(t)
    local bufnr = bucket_buffer(t)
    config.setup({ metric = 'cognitive', virtual_text = { min_complexity = 1 } })
    draw(bufnr)
    local drawn = table.concat(t.annotations(bufnr), ' ')
    t.contains(drawn, 'COG')
    t.falsy(drawn:find('CC'), 'the cyclomatic label should be gone')
  end,

  ['rendering an unsupported buffer is a no-op'] = function(t)
    local bufnr = t.buffer('yaml', 'a: 1\nb: 2')
    display.render(bufnr, analyzer.analyze(bufnr))
    t.eq(t.annotations(bufnr), {})
  end,
}

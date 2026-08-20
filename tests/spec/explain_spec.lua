local analyzer = require('cyclomatic.analyzer')
local explain = require('cyclomatic.explain')

local GO = table.concat({
  'package main',
  '',
  'func mixed(a, b, c bool, n int) int {',
  '\tif a && b && c {',
  '\t\tfor i := 0; i < n; i++ {',
  '\t\t\tif i > 2 {',
  '\t\t\t\treturn i',
  '\t\t\t}',
  '\t\t}',
  '\t} else {',
  '\t\treturn 0',
  '\t}',
  '\treturn n',
  '}',
}, '\n')

---@param entry table
---@return integer cyclomatic
---@return integer cognitive
local function totals(entry)
  local cyclomatic, cognitive = 0, 0
  for _, item in ipairs(entry.contributions) do
    cyclomatic = cyclomatic + item.cyclomatic
    cognitive = cognitive + (item.cognitive or 0)
  end
  return cyclomatic, cognitive
end

return {
  ['the account adds up to the number it explains'] = function(t)
    -- The whole point: an explanation that does not reconcile with the score is
    -- worse than none, because it invites trust in the wrong reading.
    local bufnr = t.buffer('go', GO)
    local entry = analyzer.explain(bufnr, 3)
    t.truthy(entry)
    local cyclomatic, cognitive = totals(entry)
    t.eq(cyclomatic, entry.cyclomatic, 'cyclomatic contributions')
    t.eq(cognitive, entry.cognitive, 'cognitive contributions')
  end,

  ['it adds up across every fixture, in both nesting modes'] = function(t)
    local config = require('cyclomatic.config')
    local fixtures = vim.fn.glob(t.root .. '/tests/fixtures/*/*', false, true)
    local extensions = { go = 'go', dart = 'dart', lua = 'lua', py = 'python', js = 'javascript' }

    for _, mode in ipairs({ 'inline', 'separate' }) do
      config.setup({ nested_functions = mode })
      for _, path in ipairs(fixtures) do
        local lang = extensions[path:match('%.(%w+)$')]
        local source = table.concat(vim.fn.readfile(path), '\n')
        local result = analyzer.analyze_string(source, lang, { trace = true })
        for _, entry in ipairs(result and result.entries or {}) do
          local cyclomatic, cognitive = totals(entry)
          t.eq(cyclomatic, entry.cyclomatic, path:match('[^/]+$') .. ' :: ' .. entry.name .. ' cc')
          t.eq(cognitive, entry.cognitive, path:match('[^/]+$') .. ' :: ' .. entry.name .. ' cog')
        end
      end
    end
  end,

  ['the baseline is attributed to the signature line'] = function(t)
    local bufnr = t.buffer('go', GO)
    local entry = analyzer.explain(bufnr, 3)
    local first = entry.contributions[1]
    t.eq(first.capture, 'function.body')
    t.eq(first.row, entry.row, 'not the first line of the body')
  end,

  ['contributions come back in source order'] = function(t)
    local bufnr = t.buffer('go', GO)
    local entry = analyzer.explain(bufnr, 3)
    local previous = -1
    for _, item in ipairs(entry.contributions) do
      t.truthy(item.row >= previous, 'rows must not go backwards')
      previous = item.row
    end
  end,

  ['an operator run is reported apart from its operators'] = function(t)
    -- `a && b && c` is two paths but one thing to read, and the report has to
    -- show both halves of that or the cognitive column looks wrong.
    local bufnr = t.buffer('go', GO)
    local entry = analyzer.explain(bufnr, 3)
    local operators, runs = 0, 0
    for _, item in ipairs(entry.contributions) do
      if item.capture == 'decision.flat' then
        operators = operators + 1
        t.eq(item.cognitive, nil, 'an operator defers its cognitive cost')
      elseif item.capture == 'operator run' then
        runs = runs + 1
      end
    end
    t.eq(operators, 2, 'two && operators')
    t.eq(runs, 1, 'one run between them')
  end,

  ['tracing is off unless asked for'] = function(t)
    local bufnr = t.buffer('go', GO)
    local result = analyzer.analyze(bufnr)
    t.eq(result.entries[1].contributions, nil, 'the normal path runs on every keystroke')
  end,

  ['a line inside no function is reported, not raised'] = function(t)
    local bufnr = t.buffer('go', GO)
    local entry, err = analyzer.explain(bufnr, 0)
    t.eq(entry, nil)
    t.contains(err, 'no function')
  end,

  ['the report names the function, the totals and the rules'] = function(t)
    local bufnr = t.buffer('go', GO)
    local entry = analyzer.explain(bufnr, 3)
    local text = table.concat(explain.render(entry, vim.split(GO, '\n')), '\n')
    t.contains(text, 'mixed')
    t.contains(text, 'cyclomatic ' .. entry.cyclomatic)
    t.contains(text, 'cognitive ' .. entry.cognitive)
    t.contains(text, 'nested 1 deep')
    t.contains(text, 'doc/CONTRACT.md')
  end,
}

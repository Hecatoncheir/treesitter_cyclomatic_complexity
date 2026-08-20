--- Counts checked against fixtures that carry their own expectations.
---
--- Each fixture declares `EXPECT <name> cc=<n> cog=<n>` in a comment. The Go
--- numbers are the values gocyclo and gocognit produce for those same files, so
--- these cases pin the plugin to the reference tools rather than to its own
--- previous output.
local analyzer = require('cyclomatic.analyzer')
local helpers = require('helpers')

local EXTENSIONS = { go = 'go', dart = 'dart', lua = 'lua', py = 'python' }

local spec = {}

local fixtures = vim.fn.glob(helpers.root .. '/tests/fixtures/*/*', false, true)
table.sort(fixtures)

for _, path in ipairs(fixtures) do
  local filename = path:match('[^/]+$')
  local lang = EXTENSIONS[path:match('%.(%w+)$')]

  spec['fixture ' .. filename] = function(t)
    local source = table.concat(vim.fn.readfile(path), '\n')

    local expectations, order = {}, {}
    for line in source:gmatch('[^\n]+') do
      local fn, cc, cog = line:match('EXPECT%s+(.-)%s+cc=(%d+)%s+cog=(%d+)')
      if fn then
        expectations[fn] = { cyclomatic = tonumber(cc), cognitive = tonumber(cog) }
        order[#order + 1] = fn
      end
    end
    t.truthy(#order > 0, filename .. ' declares no expectations')

    local result, err = analyzer.analyze_string(source, lang)
    t.truthy(result, 'analysis failed: ' .. tostring(err))

    local actual = {}
    for _, entry in ipairs(result.entries) do
      actual[entry.name] = entry
    end

    for _, fn in ipairs(order) do
      local want, got = expectations[fn], actual[fn]
      t.truthy(got, filename .. ' :: ' .. fn .. ' was not found')
      t.eq(
        { cyclomatic = got.cyclomatic, cognitive = got.cognitive },
        want,
        filename .. ' :: ' .. fn
      )
    end

    -- A function that appears without an expectation is as much a regression
    -- as a wrong number: it means a query started matching something new.
    for _, entry in ipairs(result.entries) do
      t.truthy(
        expectations[entry.name],
        filename .. ' :: unexpected entry ' .. entry.name .. ' (cc=' .. entry.cyclomatic .. ')'
      )
    end
  end
end

return spec

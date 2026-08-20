--- Fixture-driven test runner.
---
---   nvim --headless -l tests/run.lua
---
--- Each fixture carries its own expectations as `// EXPECT <name> cc=<n> cog=<n>`
--- comments. The Go numbers are the ones gocyclo and gocognit produce for the
--- same file, so the suite pins this plugin to the reference tools rather than
--- to its own past output.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:match('@?(.+)$'), ':h:h')
vim.opt.runtimepath:append(root)
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path

local analyzer = require('cyclomatic.analyzer')

local EXTENSIONS = { go = 'go', dart = 'dart', lua = 'lua', py = 'python' }

local passed, failed = 0, 0
local out = {}

local function log(fmt, ...)
  out[#out + 1] = select('#', ...) > 0 and fmt:format(...) or fmt
end

---@param path string
local function run_fixture(path)
  local source = table.concat(vim.fn.readfile(path), '\n')
  local lang = EXTENSIONS[path:match('%.(%w+)$')]
  local name = path:match('[^/]+$')

  local expectations, order = {}, {}
  for line in source:gmatch('[^\n]+') do
    local fn, cc, cog = line:match('EXPECT%s+(.-)%s+cc=(%d+)%s+cog=(%d+)')
    if fn then
      expectations[fn] = { cyclomatic = tonumber(cc), cognitive = tonumber(cog) }
      order[#order + 1] = fn
    end
  end

  local result, err = analyzer.analyze_string(source, lang)
  if not result then
    failed = failed + 1
    log('  FAIL %s -- analysis failed: %s', name, tostring(err))
    return
  end

  local actual = {}
  for _, entry in ipairs(result.entries) do
    actual[entry.name] = entry
  end

  for _, fn in ipairs(order) do
    local want, got = expectations[fn], actual[fn]
    if not got then
      failed = failed + 1
      log('  FAIL %s :: %s -- not found', name, fn)
    elseif got.cyclomatic ~= want.cyclomatic or got.cognitive ~= want.cognitive then
      failed = failed + 1
      log(
        '  FAIL %s :: %s -- want cc=%d cog=%d, got cc=%d cog=%d',
        name, fn, want.cyclomatic, want.cognitive, got.cyclomatic, got.cognitive
      )
    else
      passed = passed + 1
    end
  end

  for _, entry in ipairs(result.entries) do
    if not expectations[entry.name] then
      failed = failed + 1
      log('  FAIL %s :: %s -- unexpected entry (cc=%d)', name, entry.name, entry.cyclomatic)
    end
  end
end

local fixtures = vim.fn.glob(root .. '/tests/fixtures/*/*', false, true)
table.sort(fixtures)
for _, path in ipairs(fixtures) do
  run_fixture(path)
end

log('')
log('%d passed, %d failed', passed, failed)
io.stdout:write(table.concat(out, '\n') .. '\n')
os.exit(failed == 0 and 0 or 1)

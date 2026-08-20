--- Test runner.
---
---   nvim --headless -l tests/run.lua              -- everything
---   nvim --headless -l tests/run.lua analyzer     -- specs matching "analyzer"
---
--- Every file in tests/spec/ returns a table of `['what it does'] = function(t)`.
--- `t` is tests/helpers.lua. A test fails by raising, which the runner catches,
--- so one broken case never hides the rest.
-- `:p` matters: run as `nvim -l tests/run.lua`, the script path is relative,
-- and a relative runtimepath entry is not searched for query files on
-- Neovim 0.10 even though it is on later versions.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:match('@?(.+)$'), ':p:h:h')
vim.opt.runtimepath:append(root)
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path
package.path = root .. '/tests/?.lua;' .. package.path

-- `nvim -l` does not source plugin/ files, so load ours the way a real session
-- would; the integration specs drive the :Cyclomatic command.
dofile(root .. '/plugin/cyclomatic.lua')

-- The plugin notifies on several commands. Silence it so the suite's own
-- output stays readable; the specs that assert on a notification install their
-- own stub around the call they care about.
vim.notify = function() end

local helpers = require('helpers')
local filter = _G.arg and _G.arg[1]

local passed, failed, out = 0, 0, {}

---@param fmt string
local function log(fmt, ...)
  out[#out + 1] = select('#', ...) > 0 and fmt:format(...) or fmt
end

local specs = vim.fn.glob(root .. '/tests/spec/*_spec.lua', false, true)
table.sort(specs)

for _, path in ipairs(specs) do
  local name = path:match('([^/]+)_spec%.lua$')
  if not filter or name:find(filter, 1, true) then
    local ok, spec = pcall(dofile, path)
    if not ok then
      failed = failed + 1
      log('FAIL %s -- could not load: %s', name, tostring(spec))
    else
      local cases = vim.tbl_keys(spec)
      table.sort(cases)
      for _, case in ipairs(cases) do
        -- Each case starts from a clean configuration so ordering cannot
        -- leak state between them.
        helpers.configure({})
        local success, err = pcall(spec[case], helpers)
        if success then
          passed = passed + 1
        else
          failed = failed + 1
          local message = type(err) == 'table' and err.message or tostring(err)
          log('FAIL %s :: %s', name, case)
          log('       %s', message)
        end
      end
    end
  end
end

log('')
log('%d passed, %d failed', passed, failed)
io.stdout:write(table.concat(out, '\n') .. '\n')
os.exit(failed == 0 and 0 or 1)

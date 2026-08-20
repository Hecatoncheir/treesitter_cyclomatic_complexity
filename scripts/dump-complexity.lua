--- Print this plugin's numbers for a list of files, for the differential check.
---
---   nvim --headless -l scripts/dump-complexity.lua <lang> <file-list> [mode]
---
--- One tab-separated row per function: path, 1-indexed row, cyclomatic,
--- cognitive, name. `mode` is `inline` (default) or `separate`; reference tools
--- differ on whether a closure belongs to the function around it, so the
--- comparison has to be made in whichever mode the tool itself uses.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:match('@?(.+)$'), ':p:h:h')
vim.opt.runtimepath:append(root)
-- Parsers built by scripts/install-parsers.sh, which is where CI keeps them.
if vim.uv.fs_stat(root .. '/.ci/parsers') then
  vim.opt.runtimepath:append(root .. '/.ci/parsers')
end
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path

local lang, list, mode = _G.arg[1], _G.arg[2], _G.arg[3] or 'inline'
if not lang or not list then
  io.stderr:write(
    'usage: nvim --headless -l scripts/dump-complexity.lua <lang> <file-list> [mode]\n'
  )
  os.exit(2)
end

require('cyclomatic.config').setup({ nested_functions = mode })
local analyzer = require('cyclomatic.analyzer')

if not analyzer.get_query(lang) then
  io.stderr:write('no cyclomatic query for ' .. lang .. '\n')
  os.exit(1)
end

local out = {}
for path in io.lines(list) do
  local ok, lines = pcall(vim.fn.readfile, path)
  if ok then
    local result = analyzer.analyze_string(table.concat(lines, '\n'), lang)
    for _, entry in ipairs(result and result.entries or {}) do
      out[#out + 1] = table.concat({
        path,
        entry.row + 1,
        entry.cyclomatic,
        entry.cognitive,
        entry.name,
      }, '\t')
    end
  end
end

io.stdout:write(table.concat(out, '\n') .. '\n')

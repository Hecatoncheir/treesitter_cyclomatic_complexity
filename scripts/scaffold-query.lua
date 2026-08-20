--- Generate a draft cyclomatic.scm from sample code.
---
---   nvim --headless -l scripts/scaffold-query.lua <lang> <file> [file...]
---
--- Writes the draft to stdout, so it can be redirected straight into place:
---
---   nvim --headless -l scripts/scaffold-query.lua rust a.rs b.rs \
---     > queries/rust/cyclomatic.scm
---
--- Pass more than one sample. A rule cannot be guessed from code that does not
--- use it, and the draft says which constructs it never saw.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:match('@?(.+)$'), ':p:h:h')
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path

local lang = _G.arg and _G.arg[1]
local paths = {}
for index = 2, #(_G.arg or {}) do
  paths[#paths + 1] = _G.arg[index]
end

if not lang or #paths == 0 then
  io.stderr:write('usage: nvim --headless -l scripts/scaffold-query.lua <lang> <file> [file...]\n')
  os.exit(2)
end

local draft, err = require('cyclomatic.scaffold').from_files(paths, lang)
if not draft then
  io.stderr:write('error: ' .. tostring(err) .. '\n')
  os.exit(1)
end

io.stdout:write(draft)

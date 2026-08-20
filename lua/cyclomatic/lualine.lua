--- lualine component showing the complexity of the function under the cursor.
---
--- Usage:
---   sections = { lualine_x = { require('cyclomatic.lualine') } }
local config = require('cyclomatic.config')
local highlight = require('cyclomatic.highlight')

local M = {}

--- Component text, or '' when the cursor is not inside a measurable function.
---@return string
function M.status()
  local ok, entry = pcall(require('cyclomatic').current)
  if not ok or not entry then
    return ''
  end
  return string.format('%s %d', config.options.virtual_text.prefix, entry[config.options.metric])
end

--- lualine accepts a table with a function at [1]; `color` is re-evaluated on
--- every redraw, which is what lets the component change colour with the score.
M[1] = M.status
M.color = function()
  local ok, entry = pcall(require('cyclomatic').current)
  if not ok or not entry then
    return nil
  end
  return highlight.for_score(entry[config.options.metric])
end

return M

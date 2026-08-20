--- Highlight groups for the complexity annotations.
---
--- Everything links to the Diagnostic* groups by default, so the annotations
--- follow whatever colorscheme is active instead of hard-coding colours. The
--- links are `default`, so a user `:highlight` (or a colorscheme) overrides
--- them without any configuration here.
local M = {}

M.groups = {
  low = 'CyclomaticLow',
  medium = 'CyclomaticMedium',
  high = 'CyclomaticHigh',
  very_high = 'CyclomaticVeryHigh',
}

local LINKS = {
  CyclomaticLow = 'DiagnosticOk',
  CyclomaticMedium = 'DiagnosticWarn',
  CyclomaticHigh = 'DiagnosticError',
}

function M.setup()
  for group, target in pairs(LINKS) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end

  -- The worst bucket is the same red as `high` but bold, so it stands out
  -- without needing a colour the colorscheme may not define. It cannot be a
  -- link: nvim_set_hl ignores every other attribute when `link` is given, so
  -- the colour is copied out of DiagnosticError instead. The ColorScheme
  -- autocmd below re-runs this, keeping the copy in step with the theme.
  local error_hl = vim.api.nvim_get_hl(0, { name = 'DiagnosticError', link = false })
  vim.api.nvim_set_hl(0, 'CyclomaticVeryHigh', {
    fg = error_hl.fg,
    ctermfg = error_hl.ctermfg,
    bold = true,
    default = true,
  })

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('CyclomaticHighlight', { clear = true }),
    callback = function()
      M.setup()
    end,
    desc = 'Re-apply cyclomatic complexity highlight links',
  })
end

--- Highlight group for a complexity score.
---@param score integer
---@return string
function M.for_score(score)
  return M.groups[require('cyclomatic.config').bucket(score)]
end

return M

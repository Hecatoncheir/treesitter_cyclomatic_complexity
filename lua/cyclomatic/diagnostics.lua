--- Publishes complexity as diagnostics.
---
--- Going through vim.diagnostic rather than a bespoke list is what makes the
--- results show up in Trouble, the quickfix list, the statuscolumn and `]d`
--- without this plugin knowing about any of them.
local config = require('cyclomatic.config')

local M = {}

M.ns = vim.api.nvim_create_namespace('cyclomatic/diagnostics')

local SEVERITY = {
  low = vim.diagnostic.severity.HINT,
  medium = vim.diagnostic.severity.INFO,
  high = vim.diagnostic.severity.WARN,
  very_high = vim.diagnostic.severity.ERROR,
}

---@param bufnr integer
function M.clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.diagnostic.reset(M.ns, bufnr)
  end
end

---@param bufnr integer
---@param result CyclomaticResult|nil
function M.publish(bufnr, result)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local cfg = config.options
  if not cfg.diagnostics.enabled or not result then
    M.clear(bufnr)
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local items = {}
  for _, entry in ipairs(result.entries) do
    local score = entry[cfg.metric]
    if score >= cfg.diagnostics.min_complexity and entry.row < line_count then
      items[#items + 1] = {
        lnum = entry.row,
        col = 0,
        end_lnum = math.min(entry.end_row, line_count - 1),
        severity = SEVERITY[config.bucket(score)],
        source = 'cyclomatic',
        message = string.format('%s: %s complexity %d', entry.name, cfg.metric, score),
      }
    end
  end
  vim.diagnostic.set(M.ns, bufnr, items)
end

return M

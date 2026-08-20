--- Renders complexity as end-of-line virtual text.
local config = require('cyclomatic.config')
local highlight = require('cyclomatic.highlight')

local M = {}

M.ns = vim.api.nvim_create_namespace('cyclomatic')

--- Remove all annotations from a buffer.
---@param bufnr integer
function M.clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
  end
end

--- Draw annotations for an analysis result.
---@param bufnr integer
---@param result CyclomaticResult|nil
function M.render(bufnr, result)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  M.clear(bufnr)

  local cfg = config.options
  if not result or not cfg.virtual_text.enabled then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for _, entry in ipairs(result.entries) do
    local score = entry[cfg.metric]
    if score >= cfg.virtual_text.min_complexity and entry.row < line_count then
      local ok, text = pcall(cfg.virtual_text.format, entry, cfg)
      if ok and text and text ~= '' then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, entry.row, 0, {
          virt_text = { { text, highlight.for_score(score) } },
          virt_text_pos = cfg.virtual_text.position,
          hl_mode = 'combine',
          priority = cfg.virtual_text.priority,
        })
      end
    end
  end
end

return M

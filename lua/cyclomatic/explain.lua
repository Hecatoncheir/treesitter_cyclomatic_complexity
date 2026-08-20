--- Renders the account of how a function's complexity was arrived at.
---
--- A number on its own is not much use when it looks wrong: you cannot tell a
--- disagreement about the rules from a bug in the query without seeing which
--- points were counted. This prints them.
local config = require('cyclomatic.config')

local M = {}

--- Human-readable name for what a capture did.
local CAPTURES = {
  ['function.body'] = 'function baseline',
  ['decision'] = 'branch',
  ['decision.flat'] = 'operator',
  ['cyclomatic'] = 'branch (cyclomatic only)',
  ['cognitive'] = 'nesting structure',
  ['cognitive.flat'] = 'continuation (cognitive only)',
  ['operator run'] = 'operator run',
}

--- Format an entry and its contributions as report lines.
---@param entry CyclomaticEntry
---@param lines string[] buffer contents, for quoting the source
---@return string[]
function M.render(entry, lines)
  local out = {
    string.format(
      '%s  --  cyclomatic %d, cognitive %d',
      entry.name,
      entry.cyclomatic,
      entry.cognitive
    ),
    '',
    string.format('%6s  %5s  %5s  %-28s  %s', 'line', 'cc', 'cog', 'what', 'source'),
    string.rep('-', 78),
  }

  for _, item in ipairs(entry.contributions or {}) do
    local source = (lines[item.row + 1] or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if #source > 30 then
      source = source:sub(1, 28) .. '..'
    end

    -- An operator's cognitive cost is settled only once its whole run is known,
    -- so it is reported against the run rather than the operator.
    local cognitive
    if item.cognitive == nil then
      cognitive = '-'
    elseif item.cognitive == 0 then
      cognitive = ''
    else
      cognitive = '+' .. item.cognitive
    end
    local what = CAPTURES[item.capture] or item.capture
    if item.nesting and item.nesting > 0 and (item.cognitive or 0) > 1 then
      what = string.format('%s, nested %d deep', what, item.nesting)
    end

    out[#out + 1] = string.format(
      '%6d  %5s  %5s  %-28s  %s',
      item.row + 1,
      item.cyclomatic > 0 and ('+' .. item.cyclomatic) or '',
      cognitive,
      what,
      source
    )
  end

  local operators = 0
  for _, item in ipairs(entry.contributions or {}) do
    if item.capture == 'decision.flat' then
      operators = operators + 1
    end
  end
  if operators > 0 then
    out[#out + 1] = ''
    out[#out + 1] = 'Operators show `-` for cognitive because the cost of a run is settled'
    out[#out + 1] = 'only once every operator in it is known: `a and b and c` is two paths'
    out[#out + 1] = 'but one thing to read. The run is listed on its own line.'
  end

  out[#out + 1] = ''
  out[#out + 1] = string.format(
    'Metric shown in the annotation: %s. Rules: doc/CONTRACT.md',
    config.options.metric
  )
  return out
end

--- Explain the function under the cursor in a scratch buffer.
---@param winid integer|nil
function M.open(winid)
  winid = (winid == nil or winid == 0) and vim.api.nvim_get_current_win() or winid
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local row = vim.api.nvim_win_get_cursor(winid)[1] - 1

  local entry, err = require('cyclomatic.analyzer').explain(bufnr, row)
  if not entry then
    vim.notify('cyclomatic: ' .. tostring(err), vim.log.levels.WARN)
    return
  end

  local lines = M.render(entry, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))

  vim.cmd('vnew')
  local out = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(out, 0, -1, false, lines)
  vim.bo[out].buftype = 'nofile'
  vim.bo[out].bufhidden = 'wipe'
  vim.bo[out].modifiable = false
  vim.api.nvim_buf_set_name(out, 'cyclomatic-explain://' .. entry.name)
end

return M

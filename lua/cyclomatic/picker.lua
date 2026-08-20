--- Browsable list of functions, most complex first.
local config = require('cyclomatic.config')

local M = {}

---@param items table[]
---@param metric string
local function sort_by_metric(items, metric)
  table.sort(items, function(a, b)
    if a[metric] ~= b[metric] then
      return a[metric] > b[metric]
    end
    if a.file ~= b.file then
      return (a.file or '') < (b.file or '')
    end
    return a.row < b.row
  end)
end

--- Send items to the quickfix list. Always available, and picked up by
--- trouble.nvim if the user routes quickfix through it.
---@param items table[]
---@param title string
local function to_quickfix(items, title)
  local metric = config.options.metric
  local qf = {}
  for _, item in ipairs(items) do
    qf[#qf + 1] = {
      filename = item.file,
      bufnr = item.file and nil or item.bufnr,
      lnum = item.row + 1,
      col = 1,
      text = string.format('%s  %s %d', item.name, metric, item[metric]),
    }
  end
  vim.fn.setqflist({}, ' ', { title = title, items = qf })
  vim.cmd('copen')
end

--- Show items in snacks.picker when it is installed, quickfix otherwise.
---@param items table[]
---@param title string
local function show(items, title)
  local metric = config.options.metric
  sort_by_metric(items, metric)

  if #items == 0 then
    vim.notify('cyclomatic: nothing to show', vim.log.levels.INFO)
    return
  end

  local ok, snacks = pcall(require, 'snacks')
  if not ok or not snacks.picker then
    to_quickfix(items, title)
    return
  end

  local entries = {}
  for _, item in ipairs(items) do
    entries[#entries + 1] = {
      text = string.format('%4d  %s', item[metric], item.name),
      file = item.file,
      pos = { item.row + 1, 0 },
      score_value = item[metric],
      name = item.name,
    }
  end

  local shown = pcall(snacks.picker.pick, {
    source = 'cyclomatic',
    title = title,
    items = entries,
    format = 'text',
    sort = function(a, b)
      return (a.score_value or 0) > (b.score_value or 0)
    end,
  })
  if not shown then
    to_quickfix(items, title)
  end
end

--- List the functions in the current buffer.
function M.buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local result = require('cyclomatic').get(bufnr)
  if not result then
    vim.notify('cyclomatic: no complexity query for this buffer', vim.log.levels.WARN)
    return
  end
  local file = vim.api.nvim_buf_get_name(bufnr)
  local items = {}
  for _, entry in ipairs(result.entries) do
    items[#items + 1] = vim.tbl_extend('force', entry, { file = file })
  end
  show(items, 'Complexity: buffer')
end

--- Scan the whole project. Asynchronous; reports progress while it runs.
---@param root string|nil
function M.project(root)
  local notified = false
  require('cyclomatic.project').scan({
    root = root,
    on_progress = function(done, total)
      if not notified then
        notified = true
        vim.notify(string.format('cyclomatic: scanning %d files...', total), vim.log.levels.INFO)
      end
    end,
  }, function(items)
    show(items, 'Complexity: project')
  end)
end

return M

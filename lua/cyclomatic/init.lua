--- Cyclomatic and cognitive complexity, computed from tree-sitter.
---
--- Public entry point: `require('cyclomatic').setup{}`.
local analyzer = require('cyclomatic.analyzer')
local config = require('cyclomatic.config')
local diagnostics = require('cyclomatic.diagnostics')
local display = require('cyclomatic.display')
local highlight = require('cyclomatic.highlight')

local M = {}

--- Per-buffer analysis cache and debounce timers.
---@type table<integer, { tick: integer, result: CyclomaticResult|nil, timer: uv.uv_timer_t|nil, enabled: boolean|nil }>
local state = {}

local enabled = true
local augroup

---@param bufnr integer
---@return table
local function buf_state(bufnr)
  state[bufnr] = state[bufnr] or { tick = -1 }
  return state[bufnr]
end

---@param bufnr integer
---@return boolean
local function should_run(bufnr)
  if not enabled or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  local st = state[bufnr]
  if st and st.enabled == false then
    return false
  end
  if vim.bo[bufnr].buftype ~= '' then
    return false
  end

  local cfg = config.options
  local ft = vim.bo[bufnr].filetype
  if vim.tbl_contains(cfg.exclude_filetypes, ft) then
    return false
  end
  if cfg.filetypes and not vim.tbl_contains(cfg.filetypes, ft) then
    return false
  end

  local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(bufnr))
  if ok and stats and stats.size > cfg.max_filesize then
    return false
  end
  return true
end

--- Whether a complexity query exists for this buffer's language.
---@param bufnr integer|nil
---@return boolean
function M.supported(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  local lang = analyzer.buf_lang(bufnr)
  return lang ~= nil and analyzer.get_query(lang) ~= nil
end

--- Analyze a buffer now and redraw its annotations.
---@param bufnr integer|nil
---@return CyclomaticResult|nil
function M.refresh(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  if not should_run(bufnr) then
    return nil
  end

  local st = buf_state(bufnr)
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  if st.tick == tick and st.result then
    return st.result
  end

  local result = analyzer.analyze(bufnr)
  st.tick, st.result = tick, result

  display.render(bufnr, result)
  diagnostics.publish(bufnr, result)
  return result
end

--- Debounced refresh, used by the high-frequency autocmds.
---@param bufnr integer
local function schedule_refresh(bufnr)
  local st = buf_state(bufnr)
  if st.timer then
    st.timer:stop()
    st.timer:close()
    st.timer = nil
  end
  local timer = vim.uv.new_timer()
  st.timer = timer
  timer:start(config.options.debounce, 0, function()
    timer:stop()
    timer:close()
    if state[bufnr] then
      state[bufnr].timer = nil
    end
    vim.schedule(function()
      M.refresh(bufnr)
    end)
  end)
end

--- The most recent analysis for a buffer, computing it if needed.
---@param bufnr integer|nil
---@return CyclomaticResult|nil
function M.get(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  local st = state[bufnr]
  if st and st.result and st.tick == vim.api.nvim_buf_get_changedtick(bufnr) then
    return st.result
  end
  return M.refresh(bufnr)
end

--- Complexity of the function under the cursor.
---@param winid integer|nil
---@return CyclomaticEntry|nil
function M.current(winid)
  winid = (winid == nil or winid == 0) and vim.api.nvim_get_current_win() or winid
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local row = vim.api.nvim_win_get_cursor(winid)[1] - 1
  return analyzer.entry_at(M.get(bufnr), row)
end

---@param bufnr integer|nil
local function clear_buffer(bufnr)
  display.clear(bufnr)
  diagnostics.clear(bufnr)
  -- Invalidate the cache too: the analysis is still valid, but the *drawing*
  -- is gone, and refresh() short-circuits on an unchanged changedtick. Without
  -- this, re-enabling a buffer leaves it blank until the next edit.
  local st = state[bufnr]
  if st then
    st.tick = -1
  end
end

function M.disable(bufnr)
  if bufnr then
    buf_state(bufnr).enabled = false
    clear_buffer(bufnr)
  else
    enabled = false
    for buf in pairs(state) do
      clear_buffer(buf)
    end
  end
end

function M.enable(bufnr)
  if bufnr then
    buf_state(bufnr).enabled = true
    M.refresh(bufnr)
  else
    enabled = true
    M.refresh(vim.api.nvim_get_current_buf())
  end
end

---@param bufnr integer|nil
function M.toggle(bufnr)
  if bufnr then
    if buf_state(bufnr).enabled == false then
      M.enable(bufnr)
    else
      M.disable(bufnr)
    end
    return
  end
  if enabled then
    M.disable()
  else
    M.enable()
  end
end

--- Reload queries from disk. Useful while editing a cyclomatic.scm.
function M.reload()
  analyzer.reload()
  for bufnr, st in pairs(state) do
    st.tick = -1
    if vim.api.nvim_buf_is_valid(bufnr) then
      M.refresh(bufnr)
    end
  end
end

local function create_autocmds()
  augroup = vim.api.nvim_create_augroup('Cyclomatic', { clear = true })

  local immediate, deferred = {}, {}
  for _, event in ipairs(config.options.events) do
    if event == 'TextChanged' or event == 'TextChangedI' then
      deferred[#deferred + 1] = event
    else
      immediate[#immediate + 1] = event
    end
  end

  if #immediate > 0 then
    vim.api.nvim_create_autocmd(immediate, {
      group = augroup,
      callback = function(args)
        M.refresh(args.buf)
      end,
      desc = 'Recompute complexity annotations',
    })
  end

  if #deferred > 0 then
    vim.api.nvim_create_autocmd(deferred, {
      group = augroup,
      callback = function(args)
        if should_run(args.buf) then
          schedule_refresh(args.buf)
        end
      end,
      desc = 'Recompute complexity annotations (debounced)',
    })
  end

  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = augroup,
    callback = function(args)
      local st = state[args.buf]
      if st and st.timer then
        st.timer:stop()
        st.timer:close()
      end
      state[args.buf] = nil
    end,
    desc = 'Drop cached complexity state',
  })
end

---@param opts table|nil
function M.setup(opts)
  config.setup(opts)
  highlight.setup()
  create_autocmds()

  -- Annotate whatever is already open when setup runs late (lazy loading).
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      M.refresh(bufnr)
    end
  end
  return M
end

return M

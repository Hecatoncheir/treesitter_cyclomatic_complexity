--- Configuration defaults and merging.
local M = {}

---@class CyclomaticThresholds
---@field low integer      complexity at or below this is considered fine
---@field medium integer   above `low`, up to this, is worth a glance
---@field high integer     above `medium`, up to this, is worth refactoring

---@class CyclomaticConfig
M.defaults = {
  -- Metric shown in the virtual text: 'cyclomatic' or 'cognitive'.
  metric = 'cyclomatic',

  -- How closures and nested functions are attributed.
  --   'inline'   -- their branches count toward the enclosing function
  --               (what gocyclo does, and what "how hard is this function to
  --               read" usually means)
  --   'separate' -- each closure is reported as its own entry
  nested_functions = 'inline',

  -- Buckets used for colouring and diagnostic severity.
  thresholds = { low = 5, medium = 10, high = 20 },

  virtual_text = {
    enabled = true,
    -- Only annotate functions at or above this complexity. Set to 1 to
    -- annotate everything, including trivial getters.
    min_complexity = 4,
    prefix = '●',
    -- Rendered at the end of the function's signature line.
    ---@type fun(entry: table, cfg: table): string
    format = function(entry, cfg)
      local label = cfg.metric == 'cognitive' and 'COG' or 'CC'
      return string.format('%s %s %d', cfg.virtual_text.prefix, label, entry[cfg.metric])
    end,
    position = 'eol',
    priority = 100,
  },

  diagnostics = {
    enabled = false,
    -- Only publish diagnostics at or above this complexity; below it the
    -- virtual text alone is enough signal.
    min_complexity = 11,
  },

  -- Recompute triggers. TextChanged is debounced by `debounce` ms.
  events = { 'BufReadPost', 'BufWritePost', 'TextChanged', 'InsertLeave' },
  debounce = 250,

  -- nil means "every filetype that has a cyclomatic.scm query on runtimepath".
  ---@type string[]|nil
  filetypes = nil,
  exclude_filetypes = {},

  -- Buffers larger than this are skipped entirely.
  max_filesize = 512 * 1024,
}

---@type CyclomaticConfig
M.options = vim.deepcopy(M.defaults)

---@param opts table|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

--- Bucket a complexity score into a threshold name.
---@param score integer
---@return 'low'|'medium'|'high'|'very_high'
function M.bucket(score)
  local t = M.options.thresholds
  if score <= t.low then
    return 'low'
  elseif score <= t.medium then
    return 'medium'
  elseif score <= t.high then
    return 'high'
  end
  return 'very_high'
end

return M

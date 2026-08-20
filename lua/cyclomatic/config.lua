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

    -- Text between the prefix and the number. A table keeps a label per metric,
    -- which matters because `:Cyclomatic metric` switches between them while
    -- the annotations are on screen -- a single fixed string would start lying
    -- the moment it was flipped. A plain string is accepted too, and is used
    -- whichever metric is active. Set it to '' to show only the number.
    ---@type string|table<string, string>
    label = { cyclomatic = 'CC', cognitive = 'COG' },

    -- Rendered at the end of the function's signature line. Override this only
    -- to change the *shape* of the annotation; for its wording, `prefix` and
    -- `label` are enough.
    ---@type fun(entry: table, cfg: table): string
    format = function(entry, cfg)
      local parts = {}
      if cfg.virtual_text.prefix ~= '' then
        parts[#parts + 1] = cfg.virtual_text.prefix
      end
      local label = M.label()
      if label ~= '' then
        parts[#parts + 1] = label
      end
      parts[#parts + 1] = tostring(entry[cfg.metric])
      return table.concat(parts, ' ')
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

local METRICS = { cyclomatic = true, cognitive = true }
local NESTING = { inline = true, separate = true }
local POSITIONS = { eol = true, overlay = true, right_align = true, inline = true }

--- Problems with the current options, as human-readable sentences.
---
--- Used by `:checkhealth cyclomatic` and by setup(), which is the moment a typo
--- is cheapest to notice.
---@param options table|nil defaults to the active options
---@return string[]
function M.validate(options)
  options = options or M.options
  local problems = {}

  if not METRICS[options.metric] then
    problems[#problems + 1] =
      string.format("metric is %q; expected 'cyclomatic' or 'cognitive'", tostring(options.metric))
  end
  if not NESTING[options.nested_functions] then
    problems[#problems + 1] = string.format(
      "nested_functions is %q; expected 'inline' or 'separate'",
      tostring(options.nested_functions)
    )
  end

  local t = options.thresholds or {}
  if not (type(t.low) == 'number' and type(t.medium) == 'number' and type(t.high) == 'number') then
    problems[#problems + 1] = 'thresholds must all be numbers'
  elseif not (t.low < t.medium and t.medium < t.high) then
    problems[#problems + 1] =
      string.format('thresholds must increase: low=%s, medium=%s, high=%s', t.low, t.medium, t.high)
  end

  local vt = options.virtual_text or {}
  if not POSITIONS[vt.position] then
    problems[#problems + 1] = string.format('virtual_text.position is %q', tostring(vt.position))
  end
  local label_type = type(vt.label)
  if label_type ~= 'string' and label_type ~= 'table' then
    problems[#problems + 1] = 'virtual_text.label must be a string or a table keyed by metric'
  end

  return problems
end

---@param opts table|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})

  -- A bad metric used to surface as "attempt to compare number with nil" from
  -- the renderer, several steps from the typo that caused it. Say so here, and
  -- carry on with the default rather than leaving the plugin broken.
  local problems = M.validate()
  if #problems > 0 then
    for _, problem in ipairs(problems) do
      vim.notify('cyclomatic: ' .. problem, vim.log.levels.WARN)
    end
    if not METRICS[M.options.metric] then
      M.options.metric = M.defaults.metric
    end
    if not NESTING[M.options.nested_functions] then
      M.options.nested_functions = M.defaults.nested_functions
    end
  end

  return M.options
end

--- The label for whichever metric is currently being displayed.
---
--- Resolves the `virtual_text.label` option, which may be a table keyed by
--- metric or a single string covering both.
---@return string
function M.label()
  local label = M.options.virtual_text.label
  if type(label) == 'table' then
    return label[M.options.metric] or ''
  end
  return label or ''
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

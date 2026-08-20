local config = require('cyclomatic.config')

--- Run the health check with vim.health stubbed, and return what it reported.
---@return { level: string, message: string, advice: string[]|nil }[]
local function collect()
  local original = vim.health
  local calls = {}
  local function record(level)
    return function(message, advice)
      calls[#calls + 1] = { level = level, message = tostring(message), advice = advice }
    end
  end
  vim.health = {
    start = record('start'),
    ok = record('ok'),
    info = record('info'),
    warn = record('warn'),
    error = record('error'),
  }
  -- The module caches vim.health at require time, so it has to be reloaded
  -- with the stub in place.
  package.loaded['cyclomatic.health'] = nil
  local ok, err = pcall(function()
    require('cyclomatic.health').check()
  end)
  vim.health = original
  package.loaded['cyclomatic.health'] = nil
  assert(ok, tostring(err))
  return calls
end

---@param calls table[]
---@param level string
---@return string
local function messages(calls, level)
  local out = {}
  for _, call in ipairs(calls) do
    if level == nil or call.level == level then
      out[#out + 1] = call.message
      for _, line in ipairs(call.advice or {}) do
        out[#out + 1] = line
      end
    end
  end
  return table.concat(out, '\n')
end

return {
  ['every language with a query is discovered'] = function(t)
    local languages = require('cyclomatic.analyzer').languages()
    for _, expected in ipairs({ 'dart', 'go', 'lua' }) do
      t.truthy(vim.tbl_contains(languages, expected), 'missing ' .. expected)
    end
  end,

  ['a healthy setup reports each language as loading'] = function(t)
    local calls = collect()
    local ok = messages(calls, 'ok')
    t.contains(ok, 'go: parser and query both load')
    t.contains(ok, 'dart: parser and query both load')
    t.contains(ok, 'lua: parser and query both load')
    t.eq(messages(calls, 'error'), '', 'a healthy setup reports no errors')
  end,

  ['the configuration is summarised when it is valid'] = function(t)
    config.setup({ metric = 'cognitive', thresholds = { low = 3, medium = 7, high = 15 } })
    t.contains(messages(collect(), 'ok'), 'metric=cognitive')
  end,

  ['an invalid metric is reported rather than left to crash'] = function(t)
    -- It used to surface as "attempt to compare number with nil" from the
    -- renderer, several steps from the typo that caused it.
    config.options.metric = 'cyclomatick'
    t.contains(messages(collect(), 'error'), 'metric is "cyclomatick"')
  end,

  ['thresholds that do not increase are reported'] = function(t)
    config.options.thresholds = { low = 20, medium = 5, high = 1 }
    t.contains(messages(collect(), 'error'), 'thresholds must increase')
  end,

  ['validate() accepts the defaults'] = function(t)
    config.setup({})
    t.eq(config.validate(), {})
  end,

  ['validate() catches each kind of mistake'] = function(t)
    t.contains(
      table.concat(
        config.validate(vim.tbl_deep_extend('force', config.defaults, {
          nested_functions = 'sideways',
        })),
        '\n'
      ),
      'nested_functions'
    )
    t.contains(
      table.concat(
        config.validate(vim.tbl_deep_extend('force', config.defaults, {
          virtual_text = { position = 'nowhere' },
        })),
        '\n'
      ),
      'virtual_text.position'
    )
    local bad_label = vim.deepcopy(config.defaults)
    bad_label.virtual_text.label = 42
    t.contains(table.concat(config.validate(bad_label), '\n'), 'label must be')
  end,

  ['setup() falls back to a usable metric after warning'] = function(t)
    local warnings = {}
    local notify = vim.notify
    vim.notify = function(message)
      warnings[#warnings + 1] = tostring(message)
    end
    config.setup({ metric = 'cognitve' })
    vim.notify = notify

    t.contains(table.concat(warnings, '\n'), 'metric is "cognitve"')
    t.eq(config.options.metric, 'cyclomatic', 'the plugin stays usable')
  end,
}

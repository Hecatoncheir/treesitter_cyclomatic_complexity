--- Integration: the pieces wired together through lua/cyclomatic/init.lua and
--- the :Cyclomatic command.
local cyclomatic = require('cyclomatic')

local GO = table.concat({
  'package main',
  '',
  'func busy(n int) int {',
  '\tif n == 1 { return 1 }',
  '\tif n == 2 { return 2 }',
  '\tif n == 3 { return 3 }',
  '\tif n == 4 { return 4 }',
  '\treturn 0',
  '}',
}, '\n')

---@param helpers table
---@param opts table|nil
---@return integer bufnr
local function setup_buffer(helpers, opts)
  local bufnr = helpers.buffer('go', GO)
  -- An explicit prefix, so these specs assert on behaviour rather than on
  -- whichever glyph currently ships as the default.
  cyclomatic.setup(
    vim.tbl_deep_extend(
      'force',
      { virtual_text = { min_complexity = 1, prefix = '#' } },
      opts or {}
    )
  )
  cyclomatic.refresh(bufnr)
  return bufnr
end

return {
  ['setup() annotates an already-open buffer'] = function(t)
    local bufnr = setup_buffer(t)
    t.eq(t.annotations(bufnr), { 'L3 # CC 5' })
  end,

  ['get() reuses the analysis until the buffer changes'] = function(t)
    local bufnr = setup_buffer(t)
    local first = cyclomatic.get(bufnr)
    t.truthy(rawequal(cyclomatic.get(bufnr), first), 'an unchanged buffer is not re-analyzed')

    vim.api.nvim_buf_set_lines(bufnr, 3, 3, false, { '\tif n == 9 { return 9 }' })
    local second = cyclomatic.get(bufnr)
    t.falsy(rawequal(second, first), 'an edit invalidates the cache')
    t.eq(second.entries[1].cyclomatic, 6, 'and the new branch is counted')
  end,

  ['disable() clears and enable() draws again'] = function(t)
    -- Regression: clearing leaves the cached analysis in place, so re-enabling
    -- has to invalidate it or refresh() short-circuits and the buffer stays blank.
    local bufnr = setup_buffer(t)
    t.truthy(#t.annotations(bufnr) > 0)

    cyclomatic.disable()
    t.eq(t.annotations(bufnr), {}, 'disable clears the annotations')

    cyclomatic.enable()
    t.eq(t.annotations(bufnr), { 'L3 # CC 5' }, 'enable must redraw, not trust the cache')
  end,

  ['toggle() works per buffer'] = function(t)
    local bufnr = setup_buffer(t)
    cyclomatic.toggle(bufnr)
    t.eq(t.annotations(bufnr), {})
    cyclomatic.toggle(bufnr)
    t.truthy(#t.annotations(bufnr) > 0)
  end,

  ['supported() answers per language'] = function(t)
    local go_buf = t.buffer('go', GO)
    t.truthy(cyclomatic.supported(go_buf))
    local dart_buf = t.buffer('dart', 'int f() => 1;')
    t.truthy(cyclomatic.supported(dart_buf))
    local yaml_buf = t.buffer('yaml', 'a: 1')
    t.falsy(cyclomatic.supported(yaml_buf))
  end,

  ['current() reports the function under the cursor'] = function(t)
    local bufnr = setup_buffer(t)
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    local entry = cyclomatic.current()
    t.truthy(entry)
    t.eq(entry.name, 'busy')

    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    t.eq(cyclomatic.current(), nil, 'the package clause is in no function')
    t.eq(bufnr, vim.api.nvim_get_current_buf())
  end,

  ['the lualine component follows the cursor'] = function(t)
    setup_buffer(t)
    local lualine = require('cyclomatic.lualine')
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    t.eq(lualine.status(), '# 5')
    t.eq(lualine.color(), 'CyclomaticLow')

    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    t.eq(lualine.status(), '', 'outside a function the component is empty')
    t.eq(lualine.color(), nil)
  end,

  [':Cyclomatic metric flips between the two metrics'] = function(t)
    local bufnr = setup_buffer(t)
    local config = require('cyclomatic.config')
    vim.cmd('Cyclomatic metric cognitive')
    t.eq(config.options.metric, 'cognitive')
    t.contains(table.concat(t.annotations(bufnr), ' '), 'COG')

    vim.cmd('Cyclomatic metric')
    t.eq(config.options.metric, 'cyclomatic', 'no argument flips to the other one')
  end,

  [':Cyclomatic list fills the quickfix list'] = function(t)
    setup_buffer(t)
    vim.fn.setqflist({}, 'r')
    vim.cmd('Cyclomatic list')
    local qf = vim.fn.getqflist({ title = 1, items = 1 })
    t.contains(qf.title, 'Complexity')
    t.eq(#qf.items, 1)
    t.contains(qf.items[1].text, 'busy')
    vim.cmd('cclose')
  end,

  [':Cyclomatic info and refresh do not error'] = function(t)
    setup_buffer(t)
    t.truthy(pcall(vim.cmd, 'Cyclomatic info'))
    t.truthy(pcall(vim.cmd, 'Cyclomatic refresh'))
    t.truthy(pcall(vim.cmd, 'Cyclomatic reload'))
  end,

  ['an unknown subcommand is rejected, not executed'] = function(t)
    setup_buffer(t)
    local notified
    local original = vim.notify
    vim.notify = function(msg)
      notified = msg
    end
    vim.cmd('Cyclomatic nonsense')
    vim.notify = original
    t.contains(notified or '', 'unknown subcommand')
  end,

  ['exclude_filetypes skips a buffer entirely'] = function(t)
    local bufnr = t.buffer('go', GO)
    cyclomatic.setup({ virtual_text = { min_complexity = 1 }, exclude_filetypes = { 'go' } })
    cyclomatic.refresh(bufnr)
    t.eq(t.annotations(bufnr), {})
  end,

  ['filetypes restricts which buffers are annotated'] = function(t)
    local bufnr = t.buffer('go', GO)
    cyclomatic.setup({ virtual_text = { min_complexity = 1 }, filetypes = { 'dart' } })
    cyclomatic.refresh(bufnr)
    t.eq(t.annotations(bufnr), {}, 'go is not in the allowed list')
  end,
}

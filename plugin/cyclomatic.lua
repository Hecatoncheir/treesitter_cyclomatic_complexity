if vim.g.loaded_cyclomatic then
  return
end
vim.g.loaded_cyclomatic = true

if vim.fn.has('nvim-0.11') == 0 then
  vim.notify('cyclomatic.nvim requires Neovim 0.11 or newer', vim.log.levels.ERROR)
  return
end

local subcommands = {
  toggle = function()
    require('cyclomatic').toggle()
  end,
  enable = function()
    require('cyclomatic').enable()
  end,
  disable = function()
    require('cyclomatic').disable()
  end,
  refresh = function()
    require('cyclomatic').refresh(0)
  end,
  reload = function()
    require('cyclomatic').reload()
    vim.notify('cyclomatic: queries reloaded', vim.log.levels.INFO)
  end,
  list = function()
    require('cyclomatic.picker').buffer()
  end,
  project = function(args)
    require('cyclomatic.picker').project(args[1])
  end,
  metric = function(args)
    local config = require('cyclomatic.config')
    local wanted = args[1]
    if wanted ~= 'cyclomatic' and wanted ~= 'cognitive' then
      -- No argument means "show me the other one".
      wanted = config.options.metric == 'cyclomatic' and 'cognitive' or 'cyclomatic'
    end
    config.options.metric = wanted
    local cyclomatic = require('cyclomatic')
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) then
        local state = cyclomatic.get(bufnr)
        require('cyclomatic.display').render(bufnr, state)
        require('cyclomatic.diagnostics').publish(bufnr, state)
      end
    end
    vim.notify('cyclomatic: showing ' .. wanted .. ' complexity', vim.log.levels.INFO)
  end,
  explain = function()
    require('cyclomatic.explain').open(0)
  end,

  scaffold = function(args)
    local bufnr = vim.api.nvim_get_current_buf()
    local lang = args[1] or require('cyclomatic.analyzer').buf_lang(bufnr)
    if not lang then
      vim.notify('cyclomatic: no language for this buffer', vim.log.levels.ERROR)
      return
    end

    local source = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':t')
    local draft, err = require('cyclomatic.scaffold').generate(
      { { name = name ~= '' and name or '[buffer]', text = source } },
      lang
    )
    if not draft then
      vim.notify('cyclomatic: ' .. tostring(err), vim.log.levels.ERROR)
      return
    end

    -- A scratch buffer rather than a file: the draft wants reading and editing
    -- before it is worth saving to queries/<lang>/cyclomatic.scm.
    vim.cmd('vnew')
    local out = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(out, 0, -1, false, vim.split(draft, '\n'))
    vim.bo[out].filetype = 'query'
    vim.bo[out].buftype = 'nofile'
    vim.bo[out].bufhidden = 'wipe'
    vim.api.nvim_buf_set_name(out, 'cyclomatic-draft://' .. lang)
  end,

  info = function()
    local cyclomatic = require('cyclomatic')
    local bufnr = vim.api.nvim_get_current_buf()
    local lang = require('cyclomatic.analyzer').buf_lang(bufnr)
    local entry = cyclomatic.current()
    local lines = {
      'language:   ' .. tostring(lang),
      'supported:  ' .. tostring(cyclomatic.supported(bufnr)),
      'metric:     ' .. require('cyclomatic.config').options.metric,
    }
    if entry then
      lines[#lines + 1] = string.format(
        'at cursor:  %s -- cyclomatic %d, cognitive %d',
        entry.name,
        entry.cyclomatic,
        entry.cognitive
      )
    end
    vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
  end,
}

vim.api.nvim_create_user_command('Cyclomatic', function(opts)
  local args = opts.fargs
  local name = table.remove(args, 1) or 'toggle'
  local handler = subcommands[name]
  if not handler then
    vim.notify('cyclomatic: unknown subcommand ' .. name, vim.log.levels.ERROR)
    return
  end
  handler(args)
end, {
  nargs = '*',
  desc = 'Cyclomatic complexity',
  complete = function(lead, line)
    -- Only complete the subcommand itself; its arguments are free-form.
    if line:match('^%s*Cyclomatic%s+%S+%s') then
      return {}
    end
    return vim.tbl_filter(function(name)
      return name:find(lead, 1, true) == 1
    end, vim.tbl_keys(subcommands))
  end,
})

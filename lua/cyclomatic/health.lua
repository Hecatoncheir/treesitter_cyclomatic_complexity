--- `:checkhealth cyclomatic`
---
--- The failures this plugin produces in the wild are mostly not its own: a
--- parser that is missing, or one built against a tree-sitter ABI the running
--- Neovim cannot load, or a grammar whose node names have moved. All of those
--- surface as the same unhelpful "no cyclomatic query for <lang>", several
--- steps from the cause. This says what actually went wrong.
local analyzer = require('cyclomatic.analyzer')
local config = require('cyclomatic.config')

local M = {}

local health = vim.health

local MINIMUM = 'nvim-0.11'

---@param lang string
local function check_language(lang)
  -- Three different failures, three different fixes. `language.add` signals a
  -- missing parser by returning falsy and an unloadable one by raising, so both
  -- the return value and the error matter.
  local loaded, err = pcall(vim.treesitter.language.add, lang)
  if not loaded then
    local message = tostring(err)
    if message:find('ABI', 1, true) then
      health.error(
        lang .. ': parser found, but its ABI is not loadable by this Neovim',
        { message:gsub('^.-:%d+: ', ''), 'Rebuild the parser, or run a newer Neovim.' }
      )
    else
      health.error(lang .. ': parser could not be loaded', { message })
    end
    return
  end
  if not err then
    health.warn(lang .. ': no parser installed', {
      'Install it with nvim-treesitter, or `scripts/install-parsers.sh` in this repo.',
      'The query is here, so complexity will work as soon as the parser does.',
    })
    return
  end

  local query, query_err = analyzer.get_query(lang)
  if not query then
    health.error(lang .. ': query failed to compile', {
      tostring(query_err),
      'A node name in queries/' .. lang .. '/cyclomatic.scm may have changed with the grammar.',
      'See doc/ADDING-A-LANGUAGE.md.',
    })
    return
  end

  health.ok(lang .. ': parser and query both load')
end

--- Report on the buffers actually open.
---
--- Not on the *current* one: `:checkhealth` runs inside its own scratch buffer,
--- so by the time this runs the file the user was looking at is no longer
--- current. Their real question is "why is nothing showing on my file", and
--- that is answered by listing what is and is not being measured.
local function check_buffers()
  local measured, skipped = {}, {}

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(bufnr)
    if vim.api.nvim_buf_is_loaded(bufnr) and name ~= '' and vim.bo[bufnr].buftype == '' then
      local short = vim.fn.fnamemodify(name, ':t')
      local filetype = vim.bo[bufnr].filetype
      local lang = analyzer.buf_lang(bufnr)

      if not lang or not analyzer.get_query(lang) then
        skipped[#skipped + 1] =
          string.format('%s (%s)', short, filetype ~= '' and filetype or 'no filetype')
      else
        local result = analyzer.analyze(bufnr)
        if result then
          measured[#measured + 1] = string.format('%s: %d functions', short, #result.entries)
        else
          skipped[#skipped + 1] = short .. ' (analysis failed)'
        end
      end
    end
  end

  if #measured == 0 and #skipped == 0 then
    health.info('no files open')
    return
  end
  -- health.ok and health.info take no advice list, so the detail goes into the
  -- message itself; newlines are indented for us.
  if #measured > 0 then
    health.ok(string.format('%d buffer(s) measured\n%s', #measured, table.concat(measured, '\n')))
  end
  if #skipped > 0 then
    health.info(
      string.format(
        '%d buffer(s) not measured, having no query for their language\n%s',
        #skipped,
        table.concat(skipped, '\n')
      )
    )
  end
end

function M.check()
  health.start('cyclomatic.nvim')

  if vim.fn.has(MINIMUM) == 1 then
    health.ok('Neovim ' .. tostring(vim.version()))
  else
    health.error('Neovim ' .. tostring(vim.version()) .. ' is too old; 0.11 or newer is required', {
      'Neovim 0.10 loads only tree-sitter ABI 13-14, which current grammars have outgrown.',
    })
  end

  health.start('cyclomatic.nvim: languages')
  local languages = analyzer.languages()
  if #languages == 0 then
    health.error('no complexity queries found on the runtimepath', {
      'The plugin directory may not be on runtimepath.',
      'Expected files at queries/<lang>/cyclomatic.scm.',
    })
  else
    for _, lang in ipairs(languages) do
      check_language(lang)
    end
  end

  health.start('cyclomatic.nvim: configuration')
  local problems = config.validate()
  if #problems == 0 then
    health.ok(
      string.format(
        'metric=%s, nested_functions=%s, thresholds %d/%d/%d',
        config.options.metric,
        config.options.nested_functions,
        config.options.thresholds.low,
        config.options.thresholds.medium,
        config.options.thresholds.high
      )
    )
  else
    for _, problem in ipairs(problems) do
      health.error(problem)
    end
  end

  if config.options.diagnostics.enabled then
    health.info('diagnostics are on; complexity also reaches Trouble and the quickfix list')
  else
    health.info('diagnostics are off (diagnostics.enabled = true routes complexity into Trouble)')
  end

  health.start('cyclomatic.nvim: buffers')
  check_buffers()
end

return M

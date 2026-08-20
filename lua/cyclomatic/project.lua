--- Project-wide scan.
---
--- Runs off the main loop in chunks: parsing a few thousand files is far too
--- slow to do in one tick, and blocking the UI to draw a list is worse than
--- taking a moment to produce it.
local analyzer = require('cyclomatic.analyzer')
local config = require('cyclomatic.config')

local M = {}

--- Files to consider, preferring the tools that already respect .gitignore.
---@param root string
---@return string[]
local function candidate_files(root)
  local commands = {
    { 'rg', '--files', '--color', 'never', root },
    { 'git', '-C', root, 'ls-files', '--cached', '--others', '--exclude-standard' },
  }
  for _, cmd in ipairs(commands) do
    if vim.fn.executable(cmd[1]) == 1 then
      local out = vim.system(cmd, { text = true }):wait()
      if out.code == 0 and out.stdout ~= '' then
        local files = vim.split(out.stdout, '\n', { trimempty = true })
        if cmd[1] == 'git' then
          for i, f in ipairs(files) do
            files[i] = root .. '/' .. f
          end
        end
        return files
      end
    end
  end

  local files = {}
  for name, kind in vim.fs.dir(root, { depth = 10 }) do
    if kind == 'file' then
      files[#files + 1] = root .. '/' .. name
    end
  end
  return files
end

--- Tree-sitter language for a path, or nil if we cannot analyze it.
---@param path string
---@return string|nil
local function lang_of(path)
  local ft = vim.filetype.match({ filename = path })
  if not ft then
    return nil
  end
  local lang = vim.treesitter.language.get_lang(ft) or ft
  return analyzer.get_query(lang) and lang or nil
end

---@class CyclomaticProjectItem
---@field file string
---@field name string
---@field row integer
---@field end_row integer
---@field cyclomatic integer
---@field cognitive integer

--- Scan a directory tree, calling `on_done` with every function found.
---@param opts { root: string|nil, chunk: integer|nil, on_progress: fun(done: integer, total: integer)|nil }
---@param on_done fun(items: CyclomaticProjectItem[])
function M.scan(opts, on_done)
  opts = opts or {}
  local root = opts.root or vim.uv.cwd()
  local chunk = opts.chunk or 40
  local max_size = config.options.max_filesize

  local files = vim.tbl_filter(function(path)
    return lang_of(path) ~= nil
  end, candidate_files(root))

  local items, index = {}, 1
  local total = #files

  local function step()
    local stop = math.min(index + chunk - 1, total)
    for i = index, stop do
      local path = files[i]
      local stat = vim.uv.fs_stat(path)
      if stat and stat.size <= max_size then
        local fd = io.open(path, 'r')
        if fd then
          local source = fd:read('*a')
          fd:close()
          local result = analyzer.analyze_string(source, lang_of(path))
          for _, entry in ipairs(result and result.entries or {}) do
            items[#items + 1] = {
              file = path,
              name = entry.name,
              row = entry.row,
              end_row = entry.end_row,
              cyclomatic = entry.cyclomatic,
              cognitive = entry.cognitive,
            }
          end
        end
      end
    end
    index = stop + 1

    if opts.on_progress then
      opts.on_progress(math.min(index - 1, total), total)
    end

    if index > total then
      on_done(items)
    else
      vim.schedule(step)
    end
  end

  if total == 0 then
    on_done(items)
  else
    vim.schedule(step)
  end
end

return M

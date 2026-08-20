--- Print a file's syntax tree, for working out node names when adding a
--- language.
---
---   nvim --headless -l tests/tools/dump.lua <file> <lang> [max-depth]
---
--- Field names are shown as `field: node_type`, which is what the patterns in
--- queries/<lang>/cyclomatic.scm are written against. Watch in particular for
--- whether a function's body is a *child* of its signature or a *sibling* --
--- getting that wrong yields CC=1 for every function, with no error.
---
--- Anonymous children are printed too, quoted, when they occupy a field. That
--- is deliberate: `node:sexpr()` omits anonymous nodes entirely, so an operator
--- held in an `operator:` field is invisible there, and reading sexpr output
--- alone will convince you a grammar has no such field when it does.
local file, lang, max_depth = _G.arg[1], _G.arg[2], tonumber(_G.arg[3] or 99)

if not file or not lang then
  io.stderr:write('usage: nvim --headless -l tests/tools/dump.lua <file> <lang> [max-depth]\n')
  os.exit(2)
end

local source = table.concat(vim.fn.readfile(file), '\n')
local ok, parser = pcall(vim.treesitter.get_string_parser, source, lang)
if not ok then
  io.stderr:write('no parser for ' .. lang .. '\n')
  os.exit(1)
end

local out = {}
local root = parser:parse()[1]:root()

--- Name of the field `child` occupies in `parent`, if any.
---@param parent TSNode
---@param child TSNode
---@return string|nil
local function field_name(parent, child)
  -- There is no "list all fields" API, so probe the names grammars commonly use.
  for _, name in ipairs({
    'name',
    'body',
    'condition',
    'consequence',
    'alternative',
    'operator',
    'left',
    'right',
    'value',
    'initializer',
    'update',
    'parameters',
    'key',
  }) do
    for _, candidate in ipairs(parent:field(name)) do
      if candidate:id() == child:id() then
        return name
      end
    end
  end
end

local function walk(node, depth)
  if depth > max_depth then
    return
  end
  for child in node:iter_children() do
    local field = field_name(node, child)
    -- Named nodes always; anonymous ones only when they fill a field, which is
    -- where operators hide.
    if child:named() or field then
      local text = vim.treesitter.get_node_text(child, source):gsub('%s+', ' ')
      if #text > 44 then
        text = text:sub(1, 42) .. '..'
      end
      out[#out + 1] = ('%s%s%s  [%d:%d]  %s'):format(
        ('| '):rep(depth),
        field and (field .. ': ') or '',
        child:named() and child:type() or ('"' .. child:type() .. '"'),
        child:start() + 1,
        child:end_() + 1,
        text
      )
      if child:named() then
        walk(child, depth + 1)
      end
    end
  end
end

walk(root, 0)
io.stdout:write(table.concat(out, '\n') .. '\n')

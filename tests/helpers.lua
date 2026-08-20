--- Minimal assertion and buffer helpers for the test suite.
---
--- Deliberately dependency-free: the suite has to run in CI with nothing but
--- Neovim and the two compiled parsers, so it cannot lean on plenary.
local M = {}

---@class TestFailure
---@field message string

---@param message string
local function fail(message)
  error({ message = message }, 0)
end

--- Format a value for an assertion message.
---@param value any
---@return string
local function show(value)
  if type(value) == 'string' then
    return string.format('%q', value)
  end
  return vim.inspect(value):gsub('%s+', ' ')
end

---@param actual any
---@param expected any
---@param what string|nil
function M.eq(actual, expected, what)
  if not vim.deep_equal(actual, expected) then
    fail(
      string.format(
        '%sexpected %s, got %s',
        what and (what .. ': ') or '',
        show(expected),
        show(actual)
      )
    )
  end
end

---@param value any
---@param what string|nil
function M.truthy(value, what)
  if not value then
    fail(
      string.format('%sexpected a truthy value, got %s', what and (what .. ': ') or '', show(value))
    )
  end
end

---@param value any
---@param what string|nil
function M.falsy(value, what)
  if value then
    fail(
      string.format('%sexpected a falsy value, got %s', what and (what .. ': ') or '', show(value))
    )
  end
end

---@param haystack string
---@param needle string
---@param what string|nil
function M.contains(haystack, needle, what)
  if type(haystack) ~= 'string' or not haystack:find(needle, 1, true) then
    fail(
      string.format(
        '%sexpected %s to contain %s',
        what and (what .. ': ') or '',
        show(haystack),
        show(needle)
      )
    )
  end
end

--- Root of the repository.
M.root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:match('@?(.+)$'), ':h:h')

--- Create a scratch buffer with content and a filetype, and make it current.
---@param filetype string
---@param lines string[]|string
---@return integer bufnr
function M.buffer(filetype, lines)
  if type(lines) == 'string' then
    lines = vim.split(lines, '\n')
  end
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].filetype = filetype
  return bufnr
end

--- Virtual-text annotations currently drawn in a buffer, as "L<line> <text>".
---@param bufnr integer
---@return string[]
function M.annotations(bufnr)
  local ns = require('cyclomatic.display').ns
  local out = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
    out[#out + 1] = string.format('L%d %s', mark[2] + 1, mark[4].virt_text[1][1])
  end
  table.sort(out)
  return out
end

--- Highlight group of each annotation, keyed by line number.
---@param bufnr integer
---@return table<integer, string>
function M.annotation_highlights(bufnr)
  local ns = require('cyclomatic.display').ns
  local out = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
    out[mark[2] + 1] = mark[4].virt_text[1][2]
  end
  return out
end

--- Reset configuration to defaults with `overrides` applied, and drop any
--- cached analysis so the next refresh really recomputes.
---@param overrides table|nil
function M.configure(overrides)
  require('cyclomatic.config').setup(overrides)
  require('cyclomatic.highlight').setup()
end

return M

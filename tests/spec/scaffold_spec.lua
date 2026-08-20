local scaffold = require('cyclomatic.scaffold')
local helpers = require('helpers')

---@param lang string
---@param names string[]
---@return string
local function draft_for(lang, names)
  local paths = {}
  for _, name in ipairs(names) do
    paths[#paths + 1] = helpers.root .. '/tests/fixtures/' .. lang .. '/' .. name
  end
  local draft, err = scaffold.from_files(paths, lang)
  assert(draft, tostring(err))
  return draft
end

return {
  ['a generated draft is valid query syntax'] = function(t)
    -- The whole point of emitting `;` comments rather than anything else: the
    -- draft can be saved and run before a single line of it is reviewed.
    for lang, names in pairs({
      go = { 'branches.go', 'advanced.go' },
      dart = { 'forms.dart', 'branches.dart' },
      lua = { 'branches.lua' },
    }) do
      local draft = draft_for(lang, names)
      local ok, err = pcall(vim.treesitter.query.parse, lang, draft)
      t.truthy(ok, lang .. ' draft does not parse: ' .. tostring(err))
    end
  end,

  ['a body held in a sibling is anchored, not nested'] = function(t)
    -- Dart is the reason this module exists. A query that nests the signature
    -- and the body matches nothing and reports CC=1 for the whole file.
    local draft = draft_for('dart', { 'forms.dart' })
    t.contains(draft, '((function_signature) @function.signature')
    t.contains(draft, '((method_signature) @function.signature')
    t.contains(draft, 'SIBLING')
  end,

  ['a body held in a child is nested normally'] = function(t)
    local draft = draft_for('go', { 'branches.go' })
    t.contains(draft, 'body: (block) @function.body)')
    t.falsy(draft:find('SIBLING'), 'Go has no sibling bodies to warn about')
  end,

  ['closures inside a function body are found'] = function(t)
    -- They sit under an enclosing function, so the duplicate-signature filter
    -- has to stop at the body boundary or it swallows them.
    local draft = draft_for('lua', { 'branches.lua' })
    t.contains(draft, '(function_definition')
  end,

  ['a signature wrapped by a larger signature is not repeated'] = function(t)
    local draft = draft_for('dart', { 'forms.dart' })
    local _, occurrences = draft:gsub('%(function_signature%)', '')
    t.eq(occurrences, 1, 'the copy nested inside method_signature is a duplicate')
  end,

  ['operators are matched portably, not through a field'] = function(t)
    -- Whether a grammar exposes an `operator:` field varies between versions of
    -- it -- Neovim 0.12 ships a Lua grammar that has one, 0.11 one that does
    -- not -- and a query written against the field fails to parse where it is
    -- absent. Matching the token works either way.
    local draft = draft_for('go', { 'branches.go', 'cognitive.go' })
    t.contains(draft, '((binary_expression "&&") @decision.flat)')
    t.contains(draft, '((binary_expression "||") @decision.flat)')
    t.falsy(draft:find('operator:', 1, true), 'the field form is not portable')
  end,

  ['fall-through arms are left uncaptured'] = function(t)
    -- `default` opens no independent path; capturing it inflates every switch.
    local draft = draft_for('go', { 'branches.go' })
    t.contains(draft, '(expression_case) @cyclomatic')
    t.falsy(draft:find('\n%(default_case%) @'), 'default_case must not be captured')
    t.contains(draft, 'default_case')
  end,

  ['constructs the sample never used are reported as missing'] = function(t)
    local draft, err = scaffold.generate({
      { name = 'tiny.go', text = 'package main\nfunc f() int { return 1 }\n' },
    }, 'go')
    t.truthy(draft, tostring(err))
    t.contains(draft, 'NOT PRESENT IN THE SAMPLE')
    t.contains(draft, 'no boolean operators')
  end,

  ['a language without a parser is reported, not raised'] = function(t)
    local draft, err = scaffold.generate({ { name = 'x', text = 'x' } }, 'nonexistent_language')
    t.eq(draft, nil)
    t.contains(err, 'nonexistent_language')
  end,
}

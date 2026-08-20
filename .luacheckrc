-- Neovim's Lua environment.
std = 'luajit'
globals = { 'vim' }

-- Test specs receive the helpers table as `t` and are loaded with dofile.
files['tests/'] = {
  globals = { 'vim' },
}

ignore = {
  '212', -- unused argument: several callbacks take arguments they do not need
  '631', -- line too long: prose in comments is formatted for reading
}

local config = require('cyclomatic.config')

return {
  ['bucket() splits scores at the threshold boundaries'] = function(t)
    config.setup({ thresholds = { low = 5, medium = 10, high = 20 } })
    t.eq(config.bucket(1), 'low')
    t.eq(config.bucket(5), 'low', 'the boundary belongs to the lower bucket')
    t.eq(config.bucket(6), 'medium')
    t.eq(config.bucket(10), 'medium')
    t.eq(config.bucket(11), 'high')
    t.eq(config.bucket(20), 'high')
    t.eq(config.bucket(21), 'very_high')
  end,

  ['bucket() follows custom thresholds'] = function(t)
    config.setup({ thresholds = { low = 1, medium = 2, high = 3 } })
    t.eq(config.bucket(1), 'low')
    t.eq(config.bucket(2), 'medium')
    t.eq(config.bucket(3), 'high')
    t.eq(config.bucket(4), 'very_high')
  end,

  ['setup() merges deeply instead of replacing nested tables'] = function(t)
    config.setup({ virtual_text = { min_complexity = 99 } })
    t.eq(config.options.virtual_text.min_complexity, 99)
    t.eq(
      config.options.virtual_text.prefix,
      config.defaults.virtual_text.prefix,
      'untouched nested keys survive'
    )
    t.truthy(config.options.virtual_text.format, 'the default format function survives')
  end,

  ['setup() starts from defaults each time, not from the previous call'] = function(t)
    config.setup({ metric = 'cognitive' })
    t.eq(config.options.metric, 'cognitive')
    config.setup({})
    t.eq(config.options.metric, 'cyclomatic', 'a later setup resets what it does not mention')
  end,

  ['the default label follows the metric being shown'] = function(t)
    -- An explicit prefix: which glyph ships as the default is cosmetic, and a
    -- test that pins it fails for a reason that has nothing to do with labels.
    config.setup({ virtual_text = { prefix = '#' } })
    local entry = { cyclomatic = 7, cognitive = 3 }
    t.eq(config.options.virtual_text.format(entry, config.options), '# CC 7')
    config.setup({ metric = 'cognitive', virtual_text = { prefix = '#' } })
    t.eq(config.options.virtual_text.format(entry, config.options), '# COG 3')
  end,

  ['label can be set per metric'] = function(t)
    config.setup({ virtual_text = { label = { cyclomatic = 'Cyc', cognitive = 'Cog' } } })
    t.eq(config.label(), 'Cyc')
    config.options.metric = 'cognitive'
    t.eq(config.label(), 'Cog')
  end,

  ['overriding one metric leaves the other at its default'] = function(t)
    config.setup({ virtual_text = { label = { cyclomatic = 'Complexity' } } })
    t.eq(config.label(), 'Complexity')
    config.options.metric = 'cognitive'
    t.eq(config.label(), 'COG', 'the untouched half survives the merge')
  end,

  ['a plain string label covers both metrics'] = function(t)
    config.setup({ virtual_text = { label = 'CX' } })
    t.eq(config.label(), 'CX')
    config.options.metric = 'cognitive'
    t.eq(config.label(), 'CX')
  end,

  ['an empty label leaves just the prefix and the number'] = function(t)
    config.setup({ virtual_text = { prefix = '#', label = '' } })
    local entry = { cyclomatic = 7, cognitive = 3 }
    t.eq(config.options.virtual_text.format(entry, config.options), '# 7')
  end,

  ['an empty prefix and label leave only the number'] = function(t)
    config.setup({ virtual_text = { prefix = '', label = '' } })
    local entry = { cyclomatic = 7, cognitive = 3 }
    t.eq(config.options.virtual_text.format(entry, config.options), '7')
  end,
}

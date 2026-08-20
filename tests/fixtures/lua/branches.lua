local M = {}

-- EXPECT trivial cc=1 cog=0
local function trivial()
  return 1
end

-- Deliberately the same shape as the Go and Dart branch fixtures: the numbers
-- must not depend on which language the code is written in.
-- EXPECT conditions cc=5 cog=5
local function conditions(n, a, b)
  if n < 0 and a then
    return -1
  elseif n == 0 or b then
    return 0
  else
    return 1
  end
end

-- EXPECT loops cc=5 cog=5
local function loops(n, xs)
  for i = 1, n do
    while i > 0 do
      i = i - 1
    end
  end
  for _, v in ipairs(xs) do
    print(v)
  end
  repeat
    n = n - 1
  until n <= 0
  return n
end

-- `a and b or c` is Lua's ternary. Two operators, two paths -- and two
-- cognitive points, because the run changes operator halfway through.
-- EXPECT ternary cc=3 cog=2
local function ternary(a, b)
  return a and b or 'default'
end

-- EXPECT M.helper cc=2 cog=1
function M.helper(n)
  if n then
    return n
  end
  return 0
end

-- EXPECT M:method cc=2 cog=1
function M:method(n)
  if n then
    return n
  end
  return 0
end

-- A closure is folded into the function holding it by default, so `pick` gets
-- no entry of its own and its branch counts here.
-- EXPECT withClosure cc=3 cog=3
local function withClosure(xs)
  local pick = function(x)
    if x > 0 then
      return x
    end
    return 0
  end
  if xs then
    return pick(xs[1])
  end
  return 0
end

-- `goto` is Lua's only jump. It opens no new path, but it does break the
-- reader's linear flow.
-- EXPECT jumps cc=3 cog=4
local function jumps(n)
  for i = 1, n do
    if i > 2 then
      goto continue
    end
    print(i)
    ::continue::
  end
  return n
end

return M

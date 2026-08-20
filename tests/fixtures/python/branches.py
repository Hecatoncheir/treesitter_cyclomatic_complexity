# cc values are what radon 6.0.1 reports for the same code. cog values are
# computed by hand -- radon does not implement cognitive complexity.
#
# radon separates nested `def`s from their parent, as this plugin does in
# `nested_functions = 'separate'`, so the fixture avoids them; the default
# `inline` mode is exercised by `closure` below, where the difference is the
# whole point.


# EXPECT trivial cc=1 cog=0
def trivial():
    return 1


# The same branch shape as the Go, Dart and Lua fixtures: the numbers must not
# depend on which language the code is written in.
# EXPECT conditions cc=5 cog=5
def conditions(n, a, b):
    if n < 0 and a:
        return -1
    elif n == 0 or b:
        return 0
    else:
        return 1


# EXPECT loops cc=4 cog=4
def loops(n, xs):
    for i in range(n):
        while i > 0:
            i -= 1
    for x in xs:
        print(x)
    return n


# `else` on a loop runs only when it finished without `break`, so unlike an
# `if`'s `else` it opens a path of its own.
# EXPECT loop_else cc=4 cog=5
def loop_else(n):
    for i in range(n):
        if i:
            break
    else:
        return 0
    return n


# `finally` is not a branch; each `except` is, and `else` on a `try` is too.
# EXPECT handlers cc=4 cog=3
def handlers(path):
    try:
        handle = open(path)
    except FileNotFoundError:
        return None
    except PermissionError:
        return None
    else:
        return handle
    finally:
        pass


# A comprehension is a loop, and each clause of it counts.
# EXPECT comprehensions cc=5 cog=4
def comprehensions(xs, ys):
    evens = [x for x in xs if x % 2 == 0]
    pairs = {k: v for k, v in ys if k}
    return evens, pairs


# EXPECT ternary cc=2 cog=1
def ternary(n):
    return "pos" if n > 0 else "neg"


# The one place this fixture departs from radon, deliberately. `assert` is a
# conditional raise and radon counts it -- but it stops there, scoring
# `assert a and b` the same as `assert a`, while counting that same `and` in an
# `if` or a `return`. radon says 2 here; counting the operator, as everywhere
# else, gives 3.
# EXPECT asserted cc=3 cog=2
def asserted(a, b):
    assert a and b
    return a


# `case _` is the fall-through arm and opens no path. Python's grammar makes it
# identifiable, unlike most: a wildcard pattern has no named child.
# EXPECT matcher cc=3 cog=1
def matcher(command):
    match command:
        case "go":
            return 1
        case "stop":
            return 2
        case _:
            return 0


# A lambda is not given a scope of its own, so its branches count here. radon
# does the same.
# EXPECT closure cc=3 cog=2
def closure(xs):
    pick = lambda x: x if x else 0
    if xs:
        return pick(xs[0])
    return 0

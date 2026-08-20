// cc values are what ESLint 8.57's `complexity` rule reports for the same
// code -- gathered the way luacheck was for Lua: `complexity: ["error", 0]`
// so every function trips it, and the message states its score. cog values
// are computed by hand, as for every language here except Go.
//
// ESLint scores every function on its own and never folds a closure into its
// enclosing function, which is this plugin's `nested_functions = 'separate'`
// -- the same mode the Lua corpus check runs luacheck in. Checked that way,
// this plugin's cyclomatic numbers matched ESLint's on all 6766 functions
// across Node.js's own `lib/` (v22.9.0), exactly. The EXPECT values below are
// for the *default* `inline` mode instead, to match every other fixture in
// this suite -- see `withClosure` below, where the difference is the point.

// EXPECT trivial cc=1 cog=0
function trivial() {
  return 1;
}

// The same branch shape as the Go, Dart, Lua and Python fixtures: the
// numbers must not depend on which language the code is written in.
// EXPECT conditions cc=5 cog=5
function conditions(n, a, b) {
  if (n < 0 && a) {
    return -1;
  } else if (n === 0 || b) {
    return 0;
  } else {
    return 1;
  }
}

// EXPECT loops cc=4 cog=4
function loops(n, xs) {
  for (let i = 0; i < n; i++) {
    while (i > 0) {
      i--;
    }
  }
  for (const x of xs) {
    console.log(x);
  }
  return n;
}

// `for...in` and `do...while` are JS's own, beyond the shared shape above.
// EXPECT allLoops cc=6 cog=5
function allLoops(n, xs) {
  for (let i = 0; i < n; i++) {
  }
  for (const x of xs) {
    console.log(x);
  }
  for (const k in xs) {
    console.log(k);
  }
  while (n > 0) {
    n--;
  }
  do {
    n++;
  } while (n < 10);
  return n;
}

// EXPECT ternary cc=2 cog=1
function ternary(n) {
  return n > 0 ? "pos" : "neg";
}

// `??` is short-circuiting like `&&`/`||`, and counts the same way.
// EXPECT nullish cc=2 cog=1
function nullish(a, b) {
  return a ?? b;
}

// `finally` is not a branch; `catch` is, whether or not it binds a parameter.
// EXPECT handlers cc=2 cog=1
function handlers(fn) {
  try {
    fn();
  } catch (e) {
    return null;
  } finally {
    cleanup();
  }
}

// EXPECT bareCatch cc=2 cog=1
function bareCatch(fn) {
  try {
    fn();
  } catch {
    return null;
  }
}

// Two case labels stacked to share a body are two switch_case nodes in this
// grammar, unlike Go's comma-separated `case 2, 3:`, and both are counted --
// confirmed against ESLint. `default:` is not.
// EXPECT switches cc=4 cog=1
function switches(n) {
  switch (n) {
    case 1:
      return 1;
    case 2:
    case 3:
      return 2;
    default:
      return 0;
  }
}

// A generator declaration is its own node type, distinct from a plain
// function.
// EXPECT generatorFn cc=3 cog=3
function* generatorFn(n) {
  for (let i = 0; i < n; i++) {
    if (i % 2 === 0) {
      yield i;
    }
  }
}

// Only a *labelled* break/continue breaks the reader's linear flow. It adds
// no independent path, but it does cost a point to read.
// EXPECT labeled cc=5 cog=11
function labeled(xs) {
  outer: for (const x of xs) {
    for (const y of x) {
      if (y) {
        continue outer;
      }
      if (!y) {
        break outer;
      }
    }
  }
}

// `??=`, `||=` and `&&=` are short-circuiting exactly like `??`, `||` and
// `&&` -- `a ||= b` runs the assignment only when `a` is falsy -- and
// ESLint's `complexity` rule agrees: each one costs a point.
// EXPECT logicalAssign cc=4 cog=3
function logicalAssign(obj, n) {
  obj.a ??= n;
  obj.b ||= n;
  obj.c &&= n;
  return obj;
}

// Optional chaining is deliberately not a branch. `obj?.a?.b?.()` scores the
// same as `obj.a.b()` -- ESLint agrees.
// EXPECT optionalChain cc=1 cog=0
function optionalChain(obj) {
  return obj?.a?.b?.();
}

// A closure is folded into the function holding it by default -- inline
// mode, the same convention Go and Lua use -- so `pick` gets no entry of its
// own and its branch counts here instead.
// EXPECT withClosure cc=3 cog=3
function withClosure(xs) {
  const pick = function (x) {
    return x ? x : 0;
  };
  if (xs.length) {
    return pick(xs[0]);
  }
  return 0;
}

// A closure bound to a `const` is named from the binding rather than left
// <closure>.
// EXPECT bounded cc=2 cog=1
const bounded = (n) => {
  if (n) {
    return 1;
  }
  return 0;
};

// Legacy prototype assignment: a closure assigned via a plain property
// expression is named from the property, the same convention Lua uses for
// `M.f = function() end`.
// EXPECT render cc=2 cog=1
Legacy.prototype.render = function (flag) {
  if (flag) {
    return 1;
  }
  return 0;
};

// An object-literal property holding a closure is named from its key.
// EXPECT onHover cc=2 cog=1
const dispatch = {
  onHover: (flag) => (flag ? 1 : 0),
};

// Class methods, a getter, a setter, and a class field holding an arrow
// function are all named; the first three are the same node
// (method_definition) regardless of which they are.
class Widget {
  // EXPECT constructor cc=1 cog=0
  constructor(n) {
    this.n = n;
  }

  // EXPECT describe cc=2 cog=1
  describe(flag) {
    if (flag) {
      return "yes";
    }
    return "no";
  }

  // EXPECT magnitude cc=2 cog=1
  get magnitude() {
    return this.n < 0 ? -this.n : this.n;
  }

  // EXPECT retitle cc=2 cog=1
  set retitle(value) {
    if (value) {
      this.title = value;
    }
  }

  // The auto-bound handler idiom (`onClick = (e) => { ... }`) is named from
  // the field, not left <closure>.
  // EXPECT onClick cc=2 cog=1
  onClick = (e) => {
    if (e) {
      return 1;
    }
    return 0;
  };
}

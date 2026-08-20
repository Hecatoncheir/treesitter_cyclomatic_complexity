// Every shape a Dart function can take. The point of this fixture is that in
// tree-sitter-dart the signature and the body are siblings, so a query that
// nests them finds nothing at all.

// EXPECT topLevel cc=2 cog=1
int topLevel(int n) {
  if (n < 0) return -1;
  return n;
}

// EXPECT arrow cc=2 cog=1
int arrow(int n) => n > 0 ? 1 : 2;

class Widget {
  int _v = 0;

  // EXPECT Widget cc=2 cog=1
  Widget(this._v) {
    if (_v < 0) _v = 0;
  }

  // EXPECT Widget.named cc=2 cog=1
  Widget.named(int v) : _v = v {
    while (_v > 0) _v--;
  }

  // EXPECT Widget.make cc=1 cog=0
  factory Widget.make(int v) => Widget(v);

  // EXPECT get value cc=1 cog=0
  int get value => _v;

  // EXPECT set value cc=2 cog=1
  set value(int v) => _v = v < 0 ? 0 : v;

  // EXPECT scaled cc=2 cog=1
  static int scaled(int a) {
    for (var i = 0; i < a; i++) {}
    return a;
  }
}

extension IntX on int {
  // EXPECT twice cc=2 cog=1
  int twice() {
    if (this > 0) return this * 2;
    return 0;
  }
}

// EXPECT localFunctions cc=2 cog=2
int localFunctions(int n) {
  int inner(int q) {
    if (q > 0) return q;
    return 0;
  }

  return inner(n);
}

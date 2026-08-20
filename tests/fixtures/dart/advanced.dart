mixin Logging {
  // EXPECT log cc=2 cog=1
  void log(String message) {
    if (message.isNotEmpty) print(message);
  }
}

class Repo with Logging {
  final Map<String, int> _data = {};

  // base 1 + if + ?? + catch
  // EXPECT fetch cc=4 cog=3
  Future<int?> fetch(String key) async {
    if (key.isEmpty) return null;
    try {
      final cached = _data[key];
      return cached ?? await _load(key);
    } on StateError catch (e) {
      log('$e');
      return null;
    }
  }

  // EXPECT _load cc=1 cog=0
  Future<int> _load(String key) async {
    await Future<void>.delayed(Duration.zero);
    return key.length;
  }

  // A generator body (`sync*`) is still an ordinary function body.
  // EXPECT evens cc=3 cog=3
  Iterable<int> evens(List<int> xs) sync* {
    for (final x in xs) {
      if (x.isEven) yield x;
    }
  }

  // Dart 3 pattern switch. The `when` guard is not counted separately, and the
  // wildcard arm is counted like any other -- see doc/CONTRACT.md.
  // EXPECT describe cc=5 cog=1
  String describe(Object o) => switch (o) {
        int i when i > 0 => 'pos',
        int _ => 'int',
        String s => s,
        _ => 'other',
      };

  // Null-aware access and cascades add no branches of their own.
  // EXPECT configure cc=2 cog=1
  void configure(List<String>? items) {
    items
      ?..sort()
      ..forEach(log);
    if (items == null) return;
  }
}

// Record destructuring is a binding, not a branch.
// EXPECT split cc=2 cog=1
int split((int, int) pair) {
  final (a, b) = pair;
  if (a > b) return a;
  return b;
}

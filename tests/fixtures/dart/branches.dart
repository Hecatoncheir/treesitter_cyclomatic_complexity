// EXPECT conditions cc=5 cog=5
int conditions(int n, bool a, bool b) {
  if (n < 0 && a) {
    return -1;
  } else if (n == 0 || b) {
    return 0;
  } else {
    return 1;
  }
}

// EXPECT loops cc=5 cog=5
int loops(int n, List<int> xs) {
  for (var i = 0; i < n; i++) {
    while (i > 0) {
      i--;
    }
  }
  for (final x in xs) {
    print(x);
  }
  do {
    n--;
  } while (n > 0);
  return n;
}

// EXPECT switches cc=3 cog=1
int switches(int n) {
  switch (n) {
    case 0:
      return 0;
    case 1:
      return 1;
    default:
      return -1;
  }
}

// A bare `on X { }` handler produces no catch_clause, and `on X catch (e)`
// produces both an `on` token and a catch_clause -- it must still count once.
// EXPECT handlers cc=4 cog=3
int handlers(int n) {
  try {
    return n;
  } on StateError {
    return -1;
  } on ArgumentError catch (e) {
    return -2;
  } catch (e) {
    return -3;
  } finally {
    print('done');
  }
}

// Two `??` in one expression are two paths but a single cognitive run.
// EXPECT nullAware cc=3 cog=1
int nullAware(int? a, int? b) {
  return a ?? b ?? 0;
}

// EXPECT closures cc=3 cog=4
int closures(int n) {
  final f = (int x) {
    if (x > 0) return x;
    return 0;
  };
  final g = (int x) => x > 0 ? x : -x;
  return f(n) + g(n);
}

// EXPECT patterns cc=4 cog=1
String patterns(Object o) {
  return switch (o) {
    int _ => 'int',
    String _ => 'string',
    _ => 'other',
  };
}

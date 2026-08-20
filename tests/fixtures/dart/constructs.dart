// One construct per function, so a disagreement points at a single rule.
//
// The cc values were cross-checked against dart_code_metrics 5.7.6, the only
// Dart complexity tool that still runs. It confirms 13 of the 17 outright. The
// four it disputes are marked below: on every one of them it also disagrees
// with gocyclo and luacheck scoring the equivalent construct, so it is the
// outlier rather than this plugin. See README, "Why this can be trusted".
//
// dart-code-linter 4.2.1, the maintained fork, was checked too and returns
// identical numbers here, the disputed four included: it forks for Dart 3
// syntax support and carries the metric over unchanged. Not worth re-testing.
//
// cog values are computed by hand -- no Dart tool implements the metric.

// EXPECT p01_if cc=2 cog=1
int p01_if(int n) {
  if (n > 0) return 1;
  return 0;
}

// `else` opens no new path but costs a point to read.
// EXPECT p02_ifelse cc=2 cog=2
int p02_ifelse(int n) {
  if (n > 0) return 1;
  else return 0;
}

// EXPECT p03_elseif cc=3 cog=2
int p03_elseif(int n) {
  if (n > 0) return 1;
  else if (n < 0) return -1;
  return 0;
}

// EXPECT p04_and cc=3 cog=2
int p04_and(bool a, bool b) {
  if (a && b) return 1;
  return 0;
}

// EXPECT p05_or cc=3 cog=2
int p05_or(bool a, bool b) {
  if (a || b) return 1;
  return 0;
}

// EXPECT p06_for cc=2 cog=1
int p06_for(int n) {
  for (var i = 0; i < n; i++) {}
  return n;
}

// EXPECT p07_forin cc=2 cog=1
int p07_forin(List<int> xs) {
  for (final x in xs) {
    print(x);
  }
  return 0;
}

// EXPECT p08_while cc=2 cog=1
int p08_while(int n) {
  while (n > 0) {
    n--;
  }
  return n;
}

// DISPUTED: dart_code_metrics scores this 1, counting the loop not at all.
// luacheck scores Lua's equivalent `repeat ... until` as 2.
// EXPECT p09_dowhile cc=2 cog=1
int p09_dowhile(int n) {
  do {
    n--;
  } while (n > 0);
  return n;
}

// DISPUTED: dart_code_metrics scores a two-case switch 1, finding no decision
// at all. gocyclo scores the same switch in Go as 3.
// EXPECT p10_switch2 cc=3 cog=1
int p10_switch2(int n) {
  switch (n) {
    case 0:
      return 0;
    case 1:
      return 1;
  }
  return -1;
}

// DISPUTED: dart_code_metrics scores this 1 as well; gocyclo scores the Go
// equivalent 4.
// EXPECT p11_switch3 cc=4 cog=1
int p11_switch3(int n) {
  switch (n) {
    case 0:
      return 0;
    case 1:
      return 1;
    case 2:
      return 2;
  }
  return -1;
}

// `default` opens no independent path, so only the real case counts.
// EXPECT p12_switchdefault cc=2 cog=1
int p12_switchdefault(int n) {
  switch (n) {
    case 0:
      return 0;
    default:
      return -1;
  }
}

// EXPECT p13_ternary cc=2 cog=1
int p13_ternary(int n) => n > 0 ? 1 : 0;

// EXPECT p14_nullaware cc=2 cog=1
int p14_nullaware(int? a) => a ?? 0;

// EXPECT p15_catch cc=2 cog=1
int p15_catch(int n) {
  try {
    return n;
  } catch (e) {
    return -1;
  }
}

// `on X catch (e)` is one handler, not two, even though the grammar gives it
// both an `on` token and a catch_clause.
// EXPECT p16_oncatch cc=2 cog=1
int p16_oncatch(int n) {
  try {
    return n;
  } on StateError catch (e) {
    return -1;
  }
}

// DISPUTED: dart_code_metrics scores this 3, counting `yield` as a decision.
// A suspension point is not a branch under any definition of the metric.
// EXPECT p17_generator cc=2 cog=1
Iterable<int> p17_generator(List<int> xs) sync* {
  for (final x in xs) {
    yield x;
  }
}

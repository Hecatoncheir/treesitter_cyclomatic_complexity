package main

// EXPECT nestedThen cc=3 cog=3
func nestedThen(a bool) {
	if a {
		if a {
		}
	}
}

// EXPECT nestedElse cc=4 cog=5
func nestedElse(a bool) {
	if a {
	} else {
		if a {
			if a {
			}
		}
	}
}

// EXPECT nestedElseIf cc=4 cog=4
func nestedElseIf(a bool) {
	if a {
	} else if a {
		if a {
		}
	}
}

// EXPECT operatorRuns cc=11 cog=9
func operatorRuns(a, b, c, d bool) int {
	if a && b && c {
		return 1
	}
	if a && b || c {
		return 2
	}
	if a || b && c || d {
		return 3
	}
	return 0
}

// EXPECT labelledJumps cc=5 cog=11
func labelledJumps(n int) int {
outer:
	for i := 0; i < n; i++ {
		for j := 0; j < n; j++ {
			if j > 2 {
				continue outer
			}
			if j > 5 {
				break outer
			}
		}
	}
	return 0
}

// EXPECT closureInHeader cc=3 cog=3
func closureInHeader(n int) int {
	if v := func(x int) int {
		if x > 0 {
			return x
		}
		return 0
	}(n); v > 0 {
		return v
	}
	return 0
}

// EXPECT namedClosure cc=2 cog=2
func namedClosure(n int) int {
	inner := func(x int) int {
		if x > 0 {
			return x
		}
		return 0
	}
	return inner(n)
}

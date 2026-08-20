package main

// EXPECT trivial cc=1 cog=0
func trivial() int {
	return 1
}

// EXPECT conditions cc=5 cog=5
func conditions(n int, a, b, c bool) int {
	if n < 0 && a {
		return -1
	} else if n == 0 || b {
		return 0
	} else {
		return 1
	}
}

// EXPECT loops cc=5 cog=4
func loops(n int, xs []int) int {
	for i := 0; i < n; i++ {
	}
	for range xs {
	}
	for n > 0 {
		n--
	}
	for {
		break
	}
	return n
}

// EXPECT switches cc=4 cog=2
func switches(n int, i any) int {
	switch n {
	case 1:
		return 1
	case 2, 3:
		return 2
	default:
		return 0
	}
	switch i.(type) {
	case int:
		return 3
	default:
		return 4
	}
}

// EXPECT channels cc=3 cog=1
func channels(a, b chan int) {
	select {
	case <-a:
	case v := <-b:
		_ = v
	default:
	}
}

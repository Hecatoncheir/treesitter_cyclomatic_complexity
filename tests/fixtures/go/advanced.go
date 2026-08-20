package main

import "sync"

// EXPECT generic cc=3 cog=3
func generic[T comparable](xs []T, want T) int {
	count := 0
	for _, x := range xs {
		if x == want {
			count++
		}
	}
	return count
}

type Cache[K comparable, V any] struct {
	mu sync.Mutex
	m  map[K]V
}

// EXPECT Get cc=3 cog=2
func (c *Cache[K, V]) Get(k K) (V, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.m == nil {
		var zero V
		return zero, false
	}
	v, ok := c.m[k]
	if !ok {
		return v, false
	}
	return v, true
}

// EXPECT concurrent cc=4 cog=5
func concurrent(n int, done chan struct{}) {
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			if i%2 == 0 {
				return
			}
		}(i)
	}
	wg.Wait()
	select {
	case <-done:
	default:
	}
}

// EXPECT variadic cc=3 cog=3
func variadic(prefix string, parts ...string) string {
	out := prefix
	for _, p := range parts {
		if p == "" {
			continue
		}
		out += p
	}
	return out
}

// EXPECT deferred cc=3 cog=3
func deferred(n int) (err error) {
	defer func() {
		if r := recover(); r != nil {
			err = nil
		}
	}()
	if n < 0 {
		panic("negative")
	}
	return nil
}

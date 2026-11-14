package engine

// The random numbers: a pure function of its key, even in [0, 1), and no collision between the keys a step uses.

import "core:fmt"
import "core:testing"

@(test)
the_same_key_gives_the_same_number :: proc(t: ^testing.T) {
	k := Rng_Key{seed = 2026, step = 12, agent = 7, use = .Production}
	for _ in 0 ..< 8 {
		testing.expect(t, rng_next(k) == rng_next(k), "one key gave two numbers")
	}
}

@(test)
a_step_draws_differently_for_each_agent_and_use :: proc(t: ^testing.T) {
	seen := make(map[u64]bool, 1_000)
	defer delete(seen)
	for agent in 0 ..< 100 {
		for use in Use {
			v := rng_next({seed = 2026, step = 1, agent = u32(agent), use = use})
			testing.expectf(t, v not_in seen, "agent %d use %v repeated a number", agent, use)
			seen[v] = true
		}
	}
}

@(test)
a_unit_draw_stays_between_zero_and_one :: proc(t: ^testing.T) {
	for i in 0 ..< 10_000 {
		k := Rng_Key{seed = 1, step = u64(i), agent = u32(i * 7), use = .Move}
		u := rng_unit(k)
		if u < 0 || u >= 1 { testing.fail_now(t, fmt.tprintf("a unit draw was %v", u)) }
	}
}

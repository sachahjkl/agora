package engine

// The tests that break the design on day one: the books of every step, the same run for the same seed, sensors that
// change nothing, and a seed that founds the world.

import "core:fmt"
import "core:slice"
import "core:testing"

// A small world, quick to build and to step: dense enough that a cell holds buyers and sellers at once.
small_world :: proc(seed: u64, agents: int = 2_000) -> World {
	return world_make({width = 16, height = 8, agents = agents, seed = seed})
}

// Everything an agent holds, for a byte-for-byte comparison of two runs.
snapshot :: proc(w: ^World) -> []i64 {
	out := make([]i64, w.agents.count * 5)
	for a in 0 ..< w.agents.count {
		out[a * 5 + 0] = i64(w.agents.cell[a])
		out[a * 5 + 1] = w.agents.goods[a]
		out[a * 5 + 2] = w.agents.money[a]
		out[a * 5 + 3] = i64(w.agents.hunger[a])
		out[a * 5 + 4] = i64(w.agents.health[a])
	}
	return out
}

@(test)
the_books_balance_at_every_step :: proc(t: ^testing.T) {
	for seed in ([3]u64{1, 7, 2026}) {
		w := small_world(seed)
		defer world_destroy(&w)
		traded: i64
		trades: u64
		for _ in 0 ..< 400 {
			world_step(&w)
			traded += w.books.traded
			trades += w.books.trades
			if why := books_why(&w); why != "" {
				testing.fail_now(t, fmt.tprintf("seed %d, step %d: %s", seed, w.step, why))
			}
		}
		testing.expect(t, traded > 0, "the market traded nothing")
		testing.expect(t, trades > 0, "no market ever cleared")
		testing.expect(t, w.measures.goods != 0, "the world holds no goods")
		testing.expect(t, w.measures.money > 0, "the world holds no money")
	}
}

@(test)
the_same_seed_gives_the_same_run :: proc(t: ^testing.T) {
	a := small_world(42)
	defer world_destroy(&a)
	b := small_world(42)
	defer world_destroy(&b)
	for _ in 0 ..< 200 {
		world_step(&a)
		world_step(&b)
	}
	sa, sb := snapshot(&a), snapshot(&b)
	defer delete(sa)
	defer delete(sb)
	if !slice.equal(sa, sb) {
		testing.fail_now(t, "two runs of seed 42 differ")
	}
	testing.expect(t, a.books == b.books, "the books of two runs of seed 42 differ")
}

@(test)
another_seed_founds_another_world :: proc(t: ^testing.T) {
	a := small_world(1)
	defer world_destroy(&a)
	b := small_world(2)
	defer world_destroy(&b)
	sa, sb := snapshot(&a), snapshot(&b)
	defer delete(sa)
	defer delete(sb)
	testing.expect(t, !slice.equal(sa, sb), "two seeds founded the same world")
}

@(test)
sensors_change_nothing :: proc(t: ^testing.T) {
	plain := small_world(9)
	defer world_destroy(&plain)
	watched := small_world(9)
	defer world_destroy(&watched)
	_ = sensor_add(&watched, .Total, .Goods, 1)
	_ = sensor_add(&watched, .Mean, .Money, 1)
	_ = sensor_add(&watched, .Gini, .Money, 5)
	_ = sensor_add(&watched, .Mean, .Hunger, 1)
	for _ in 0 ..< 200 {
		world_step(&plain)
		world_step(&watched)
	}
	sa, sb := snapshot(&plain), snapshot(&watched)
	defer delete(sa)
	defer delete(sb)
	if !slice.equal(sa, sb) {
		testing.fail_now(t, "a sensor changed the world it measures")
	}
	testing.expect(t, watched.sensors.slots[2].count > 0, "the Gini sensor took no sample")
}

@(test)
the_hunger_falls_when_food_is_plentiful :: proc(t: ^testing.T) {
	w := world_make({width = 32, height = 16, agents = 1_000, seed = 3})
	defer world_destroy(&w)
	before := f64(w.measures.hunger)
	for _ in 0 ..< 150 { world_step(&w) }
	after := f64(w.measures.hunger) / f64(w.measures.count)
	testing.expect(t, after < 100, "the mean hunger is not a mean")
	testing.expectf(t, after < f64(w.agents.count) * 100, "the hunger did not fall (%.1f, from %.1f)", after, before / f64(w.agents.count))
}

@(test)
gini_is_zero_for_equals_and_high_for_one :: proc(t: ^testing.T) {
	w := world_make({width = 8, height = 8, agents = 100, seed = 5})
	defer world_destroy(&w)
	for a in 0 ..< w.agents.count { w.agents.money[a] = 1_000 }
	testing.expectf(t, gini(&w, .Money, w.agents.count) < 0.0001, "equal wealth gave a Gini of %v", gini(&w, .Money, w.agents.count))
	w.agents.money[0] = 1_000_000_000
	for a in 1 ..< w.agents.count { w.agents.money[a] = 0 }
	testing.expectf(t, gini(&w, .Money, w.agents.count) > 0.9, "one rich agent gave a Gini of %v", gini(&w, .Money, w.agents.count))
}

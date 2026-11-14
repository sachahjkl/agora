package engine

// Counter-based randomness. A number is a pure function of (seed, step, agent, use): no state is carried from one call
// to the next, so the order of the calls, the partition of the agents and the number of threads change nothing.

// What a draw is for. One use per purpose, so that two draws of one agent in one step never give the same number.
Use :: enum u32 {
	// the founding of the world, at step 0
	Home = 1,
	Goods,
	Money,
	Hunger,
	Health,
	// the step's draws
	Production,
	Skill,
	Move,
	Intention,
	Health_Change,
}

Rng_Key :: struct {
	seed:  u64,
	step:  u64,
	agent: u32,
	use:   Use,
}

// splitmix64: a 64-bit mixer with a full period, cheap and well distributed.
splitmix64 :: proc(x: u64) -> u64 {
	z := x + 0x9E3779B97F4A7C15
	z = (z ~ (z >> 30)) * 0xBF58476D1CE4E5B9
	z = (z ~ (z >> 27)) * 0x94D049BB133111EB
	return z ~ (z >> 31)
}

rng_next :: proc(k: Rng_Key) -> u64 {
	return rng_at(splitmix64(k.seed ~ splitmix64(k.step)), k.agent, k.use)
}

// A draw from a step's root (World.step_seed, rng_step_seed): one mixer, for the many draws of a step.
rng_at :: proc(step_seed: u64, agent: u32, use: Use) -> u64 {
	return splitmix64(step_seed ~ (u64(agent) << 32 | u64(use)))
}

// A number in [lo, hi) from a step's root, lo when the range is empty.
rng_range_at :: proc(step_seed: u64, agent: u32, use: Use, lo, hi: i64) -> i64 {
	if hi <= lo { return lo }
	return lo + i64(rng_at(step_seed, agent, use) % u64(hi - lo))
}

// A number in [0, 1), from the 53 bits a f64 holds exactly.
rng_unit :: proc(k: Rng_Key) -> f64 {
	return f64(rng_next(k) >> 11) * (1.0 / 9007199254740992.0)
}

// A number in [lo, hi), lo when the range is empty.
rng_range :: proc(k: Rng_Key, lo, hi: i64) -> i64 {
	if hi <= lo { return lo }
	return lo + i64(rng_next(k) % u64(hi - lo))
}

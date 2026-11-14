package engine

// Sensors: the only way to observe a running world. A sensor is a reduction over a field of the agents, taken at its own
// rate, kept in a ring of samples. It reads the step's aggregates (measure) and never changes the world, so a run with
// sensors and a run without them end in the same state.

import "core:fmt"

Field :: enum u8 {
	Goods,
	Money,
	Hunger,
	Health,
}

Sensor_Kind :: enum u8 {
	Total, // the sum over every agent
	Mean,  // the mean over every agent
	Gini, // the exact inequality of the field, sorted at the sensor's rate
}

SENSOR_SLOTS   :: 32
SENSOR_SAMPLES :: 512

Sensor :: struct {
	kind:   Sensor_Kind,
	field:  Field,
	every:  u32, // steps between two samples (1: every step)
	count:  int, // samples kept, up to SENSOR_SAMPLES
	next:   int, // where the next sample goes
	values: [SENSOR_SAMPLES]f64,
}

Sensors :: struct {
	count: int,
	slots: [SENSOR_SLOTS]Sensor,
}

// A sensor attached to the world, at `every` steps; its slot (a small integer, its identity).
sensor_add :: proc(w: ^World, kind: Sensor_Kind, field: Field, every: u32) -> int {
	assert(w.sensors.count < SENSOR_SLOTS, "no sensor slot left")
	slot := w.sensors.count
	w.sensors.slots[slot] = {kind = kind, field = field, every = max(every, 1)}
	w.sensors.count += 1
	return slot
}

// The sensor's last sample (0 when it has none).
sensor_latest :: proc(w: ^World, slot: int) -> f64 {
	s := &w.sensors.slots[slot]
	if s.count == 0 { return 0 }
	return s.values[(s.next - 1 + SENSOR_SAMPLES) % SENSOR_SAMPLES]
}

// A sample `back` steps before the last (0: the last).
sensor_sample :: proc(w: ^World, slot: int, back: int) -> f64 {
	s := &w.sensors.slots[slot]
	if back < 0 || back >= s.count { return 0 }
	return s.values[(s.next - 1 - back + SENSOR_SAMPLES * 2) % SENSOR_SAMPLES]
}

// The samples a sensor took, oldest first, into `out` (at most its length).
sensor_history :: proc(w: ^World, slot: int, out: []f64) -> int {
	s := &w.sensors.slots[slot]
	n := min(len(out), s.count)
	for i in 0 ..< n {
		out[i] = s.values[(s.next - n + i + SENSOR_SAMPLES * 2) % SENSOR_SAMPLES]
	}
	return n
}

// The sensors due at this step, computed from the aggregates of measure (a Gini sorts the field).
sensors_measure :: proc(w: ^World) {
	for i in 0 ..< w.sensors.count {
		s := &w.sensors.slots[i]
		if s.every > 1 && w.step % u64(s.every) != 0 { continue }
		s.values[s.next] = sensor_compute(w, s)
		s.next = (s.next + 1) % SENSOR_SAMPLES
		s.count = min(s.count + 1, SENSOR_SAMPLES)
	}
}

@(private = "file")
sensor_compute :: proc(w: ^World, s: ^Sensor) -> f64 {
	m := &w.measures
	if s.kind == .Gini { return gini(w, s.field, w.agents.count) }
	total: i64
	switch s.field {
	case .Goods:
		total = m.goods
	case .Money:
		total = m.money
	case .Hunger:
		total = m.hunger
	case .Health:
		total = m.health
	}
	if s.kind == .Total { return s.field == .Goods ? f64(total) / GOOD : f64(total) }
	return m.count > 0 ? f64(total) / f64(m.count) : 0
}

// The always-on aggregates, for a report: the count, the totals, the means, and the share of wealth in the top bucket.
Report :: struct {
	step:     u64,
	agents:   int,
	goods:    i64,
	money:    i64,
	produced: i64,
	consumed: i64,
	traded:   i64,
	trades:   u64,
	hunger:   f64,
	health:   f64,
	starving: f64, // the share of the people above STARVING, in percent
}

report :: proc(w: ^World) -> Report {
	m := &w.measures
	r := Report {
		step     = w.step,
		agents   = m.count,
		goods    = m.goods / GOOD,
		money    = m.money,
		produced = w.books.produced / GOOD,
		consumed = w.books.consumed / GOOD,
		traded   = w.books.traded / GOOD,
		trades   = w.books.trades,
	}
	if m.count > 0 {
		r.hunger = f64(m.hunger) / f64(m.count)
		r.health = f64(m.health) / f64(m.count)
		r.starving = 100 * f64(m.starving) / f64(m.count)
	}
	return r
}

// One line of a report, for the command line (the viewer will read the same values through the sensors).
report_line :: proc(r: Report) -> string {
	return fmt.tprintf(
		"step %6d  goods %10d  money %12d  hunger %5.1f  starving %4.1f%%  health %5.1f  trades %8d  eaten %8d",
		r.step, r.goods, r.money, r.hunger, r.starving, r.health, r.trades, r.consumed,
	)
}

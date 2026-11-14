package engine

// A cell's people, for the viewer's inspector: who they are, what they hold, how hungry they are. Read by the engine
// thread on demand, from the world it is stepping; the viewer only ever sees the copy in its snapshot.

Probe :: struct {
	id:     u32,
	money:  i64,
	goods:  i64,
	hunger: u8,
	health: u8,
	skill:  u8,
}

// Up to `len(out)` of the cell's agents, in their own order; how many were written.
probe_agents :: proc(w: ^World, cell: u32, out: []Probe) -> int {
	n := 0
	for a in 0 ..< w.agents.count {
		if w.agents.cell[a] != cell { continue }
		if n >= len(out) { break }
		out[n] = {
			id     = u32(a),
			money  = w.agents.money[a],
			goods  = w.agents.goods[a],
			hunger = w.agents.hunger[a],
			health = w.agents.health[a],
			skill  = w.agents.skill[a],
		}
		n += 1
	}
	return n
}

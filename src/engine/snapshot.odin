package engine

// The viewer's map: the per-cell sums of the agents, one pass, into buffers the caller owns. The viewer copies what it
// reads; it never looks at the world itself.

cells_snapshot :: proc(w: ^World, people, hunger: []u32, money, goods: []i64) {
	cells := w.width * w.height
	assert(len(people) >= cells && len(hunger) >= cells && len(money) >= cells && len(goods) >= cells)
	for c in 0 ..< cells {
		people[c] = 0
		hunger[c] = 0
		money[c] = 0
		goods[c] = 0
	}
	for a in 0 ..< w.agents.count {
		c := w.agents.cell[a]
		people[c] += 1
		hunger[c] += u32(w.agents.hunger[a])
		money[c] += w.agents.money[a]
		goods[c] += w.agents.goods[a]
	}
}

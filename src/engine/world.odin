package engine

// The world: a grid of cells and the agents in it, in columns (structure of arrays). One step: sort the agents by market,
// produce, state intentions, resolve each market, eat, then modulate and measure.

import "core:mem"
import "core:slice"
import "base:intrinsics"

// A cell of the grid: what the land gives to a healthy, skilled person (per thousand), its height, its biome, its
// climate. Ocean and ice give nothing, and no one lives there.
Cell :: struct {
	productivity: u16,
	elevation:    u16,
	biome:        Biome,
	temperature:  u8,
	moisture:     u8,
}

// A market: the price of a good there, and how many buyers and sellers its last step had. A region of REGION × REGION
// cells holds one, so that poor and rich land meet in the same market.
Market :: struct {
	price:   i64,
	buyers:  int,
	sellers: int,
}

// One agent's columns. Everything the step reads each time is here, and nothing else.
Agents :: struct {
	count:  int,
	cell:   []u32,
	goods:  []i64,
	money:  []i64,
	hunger: []u8, // 0 (fed) to 100 (starving)
	health: []u8, // 0 to 100
	skill:  []u8, // 50 to 150: what this person gets out of the land, in percent
}

// What an agent wants in this step's market, written before any market is resolved.
Side :: enum u8 {
	None,
	Buy,
	Sell,
}

Intent :: struct {
	side: Side,
	qty:  u32,
}

// The step's books, for the conservation test: goods produced and eaten, money moved, and the totals at both ends.
Books :: struct {
	goods_start: i64,
	money_start: i64,
	produced:    i64,
	consumed:    i64,
	traded:      i64,
	trades:      u64,
	money_moved: i64,
	goods_end:   i64,
	money_end:   i64,
}

// The always-on aggregates of one measurement pass, from which sensors read.
Measures :: struct {
	count:    int,
	goods:    i64,
	money:    i64,
	hunger:   i64,
	health:   i64,
	starving: int, // agents above STARVING
	wealth:   [WEALTH_BUCKETS]u64, // log2 buckets of money, 0 to 63
	wealth_n: u64,
}

World :: struct {
	seed:   u64,
	step:   u64,
	width:  int,
	height: int,
	cells:  []Cell,
	// the markets: REGION × REGION cells each, and where their agents are in `order`
	markets_x:    int,
	markets_y:    int,
	markets:      []Market,
	market_start: []u32,
	agents:       Agents,
	// the agents in market order: order[market_start[m] ..< market_start[m+1]] are the agents of market m
	order:       []u32,
	cell_cursor: []u32,
	intents:     []Intent,
	// the land the people can stand on, and how many stand on each cell (the map's density, and migration's crowding)
	land:     []u32,
	cell_pop: []u32,
	books:       Books,
	measures:    Measures,
	sensors:     Sensors,
	scratch:     []i64, // the field, for an exact Gini
	// the step's randomness root: splitmix64(seed ~ splitmix64(step)), one mixer per draw
	step_seed: u64,
	allocator: mem.Allocator,
}

// The constants of the economy. They are the model's dials; the command line gives the ones a run needs. Goods are in
// centi-units (a hundredth of a meal) and money in its smallest unit, so that no division loses anything.
GOOD :: 100 // centi-units in one unit
REGION          :: 4      // cells across and down one market
PRODUCE_DIVISOR :: 20000  // productivity × health × skill, divided: about 2.5 units a step on average land
PRICE_BASE      :: 50000  // a market's price: PRICE_BASE / its mean productivity, money per unit
EAT_PER_UNIT    :: 10     // hunger removed by one unit eaten
HUNGER_PER_STEP :: 20     // hunger added by one step: about 2 units, near the average output
SURPLUS         :: 3 * GOOD // goods an agent keeps before selling
BUY_BELOW       :: 20     // an agent buys when its hunger is above this
MIGRATE_EVERY   :: 4      // an agent's turn to move comes up every 4 steps
MIGRATE_HUNGER  :: 40     // below this hunger, a person stays where it is
STARVING        :: 70     // above this hunger, health falls
WEALTH_BUCKETS  :: 64

World_Options :: struct {
	width:  int,
	height: int,
	agents: int,
	seed:   u64,
}

world_make :: proc(o: World_Options) -> World {
	assert(o.width > 0 && o.height > 0, "the grid needs a size")
	assert(o.agents > 0, "the world needs people")
	w := World {
		seed   = o.seed,
		width  = o.width,
		height = o.height,
	}
	w.allocator = context.allocator
	cells := o.width * o.height
	w.cells = make([]Cell, cells)
	w.order = make([]u32, o.agents)
	w.cell_cursor = make([]u32, o.agents)
	w.intents = make([]Intent, o.agents)
	w.scratch = make([]i64, o.agents)
	w.agents.count = o.agents
	w.agents.cell = make([]u32, o.agents)
	w.agents.goods = make([]i64, o.agents)
	w.agents.money = make([]i64, o.agents)
	w.agents.hunger = make([]u8, o.agents)
	w.agents.health = make([]u8, o.agents)
	w.agents.skill = make([]u8, o.agents)

	// The ground: continents and oceans, climates and biomes, all from the seed; then the markets, one per region, each
	// at the price its land gives: poor land, dear food.
	land := terrain_generate(w.cells, o.width, o.height, o.seed)
	w.land = make([]u32, len(land))
	copy(w.land, land[:])
	delete(land)
	assert(len(w.land) > 0, "the world has no land")

	w.markets_x = max(1, (o.width + REGION - 1) / REGION)
	w.markets_y = max(1, (o.height + REGION - 1) / REGION)
	w.markets = make([]Market, w.markets_x * w.markets_y)
	w.market_start = make([]u32, len(w.markets) + 1)
	for my in 0 ..< w.markets_y {
		for mx in 0 ..< w.markets_x {
			mean, n := 0, 0
			for y in my * REGION ..< min((my + 1) * REGION, o.height) {
				for x in mx * REGION ..< min((mx + 1) * REGION, o.width) {
					mean += int(w.cells[y * o.width + x].productivity)
					n += 1
				}
			}
			productivity := n > 0 ? mean / n : 500
			if productivity <= 0 { productivity = 200 } // (a region of open sea: a price nobody uses, but no division by zero)
			w.markets[my * w.markets_x + mx] = {price = PRICE_BASE / i64(productivity)}
		}
	}

	// The people: a cell of land, a small stock, some money, a little hunger, decent health, a skill. Each from the seed
	// alone: the same seed founds the same world, and each field from its own stream (Rng_Key.use).
	w.cell_pop = make([]u32, cells)
	for a in 0 ..< o.agents {
		k := Rng_Key{seed = o.seed, step = 0, agent = u32(a)}
		k.use = .Home
		at := rng_range(k, 0, i64(len(w.land)))
		w.agents.cell[a] = w.land[at]
		w.cell_pop[w.agents.cell[a]] += 1
		k.use = .Goods
		w.agents.goods[a] = rng_range(k, 2 * GOOD, 8 * GOOD)
		k.use = .Money
		w.agents.money[a] = rng_range(k, 20_000, 60_000)
		k.use = .Hunger
		w.agents.hunger[a] = u8(rng_range(k, 10, 50))
		k.use = .Health
		w.agents.health[a] = u8(rng_range(k, 70, 100))
		k.use = .Skill
		w.agents.skill[a] = u8(rng_range(k, 70, 131))
	}
	measure(&w)
	return w
}

world_destroy :: proc(w: ^World) {
	delete(w.cells, w.allocator)
	delete(w.land, w.allocator)
	delete(w.cell_pop, w.allocator)
	delete(w.markets, w.allocator)
	delete(w.market_start, w.allocator)
	delete(w.order, w.allocator)
	delete(w.cell_cursor, w.allocator)
	delete(w.intents, w.allocator)
	delete(w.scratch, w.allocator)
	delete(w.agents.cell, w.allocator)
	delete(w.agents.goods, w.allocator)
	delete(w.agents.money, w.allocator)
	delete(w.agents.hunger, w.allocator)
	delete(w.agents.health, w.allocator)
	delete(w.agents.skill, w.allocator)
	w^ = {}
}

// The step's randomness root: one mixer for the step, then one per draw (rng_at).
rng_step_seed :: proc(w: ^World) {
	w.step_seed = splitmix64(w.seed ~ splitmix64(w.step))
}

// One step of the world, its phases in a fixed order: each reads the state at t and writes the state at t+1.
world_step :: proc(w: ^World) {
	w.step += 1
	rng_step_seed(w)
	sort_by_market(w)
	produce_and_intend(w)
	resolve_markets(w)
	eat_and_modulate(w)
	migrate(w)
	measure(w)
	assert(books_balanced(w), "the books of the step do not balance")
}

// The market a cell belongs to.
market_of :: proc(w: ^World, cell: u32) -> int {
	x := int(cell) % w.width
	y := int(cell) / w.width
	return (y / REGION) * w.markets_x + x / REGION
}

// The agents in market order, by a stable counting sort: the agents of a market are contiguous, in their own order, so
// every market visits them in a fixed, seed-given order. Linear, and it compacts any hole a death leaves. Its first loop
// is also where the step's books open: one pass over the agents does both.
sort_by_market :: proc(w: ^World) {
	w.books = {}
	for m in 0 ..= len(w.markets) { w.market_start[m] = 0 }
	for a in 0 ..< w.agents.count {
		w.market_start[market_of(w, w.agents.cell[a]) + 1] += 1
		w.books.goods_start += w.agents.goods[a]
		w.books.money_start += w.agents.money[a]
	}
	for m in 0 ..< len(w.markets) { w.market_start[m + 1] += w.market_start[m] }
	copy(w.cell_cursor[:len(w.markets)], w.market_start[:len(w.markets)])
	for a in 0 ..< w.agents.count {
		m := market_of(w, w.agents.cell[a])
		w.order[w.cell_cursor[m]] = u32(a)
		w.cell_cursor[m] += 1
	}
}

// Each agent works its land, then says what it wants at its market's price: money for what it holds beyond its keep,
// else food when it is hungry and short. One side only: an agent that sells does not buy in the same step. One pass.
produce_and_intend :: proc(w: ^World) {
	for a in 0 ..< w.agents.count {
		c := w.agents.cell[a]
		base := i64(w.cells[c].productivity) * i64(w.agents.health[a]) * i64(w.agents.skill[a])
		centi := base * GOOD / (PRODUCE_DIVISOR * 100)
		luck := rng_range_at(w.step_seed, u32(a), .Production, 80, 121)
		centi = centi * luck / 100
		w.agents.goods[a] += centi
		w.books.produced += centi

		w.intents[a] = {}
		price := w.markets[market_of(w, c)].price
		if price <= 0 { continue }
		if w.agents.goods[a] > SURPLUS {
			w.intents[a] = {side = .Sell, qty = u32(w.agents.goods[a] - SURPLUS)}
			continue
		}
		if w.agents.hunger[a] > BUY_BELOW {
			want := (100 - i64(w.agents.hunger[a])) * (GOOD / EAT_PER_UNIT)
			afford := w.agents.money[a] * GOOD / price
			if qty := min(want, afford); qty > 0 {
				w.intents[a] = {side = .Buy, qty = u32(qty)}
			}
		}
	}
}

// A hungry person moves to the neighbouring land that holds fewer people for what it gives: the poorest land empties,
// the river's banks fill. No draw: a fixed turn and a fixed order of the four neighbours keep the run deterministic.
migrate :: proc(w: ^World) {
	for a in 0 ..< w.agents.count {
		if (a + int(w.step)) % MIGRATE_EVERY != 0 { continue }
		if w.agents.hunger[a] < MIGRATE_HUNGER { continue }
		c := w.agents.cell[a]
		x, y := int(c) % w.width, int(c) / w.width
		best := c
		best_score := crowd_score(w, c)
		neighbours := [4][2]int{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
		for d in neighbours {
			nx, ny := x + d[0], y + d[1]
			if nx < 0 || ny < 0 || nx >= w.width || ny >= w.height { continue }
			nc := u32(ny * w.width + nx)
			if w.cells[nc].productivity == 0 { continue }
			if score := crowd_score(w, nc); score > best_score {
				best_score, best = score, nc
			}
		}
		if best != c {
			w.cell_pop[c] -= 1
			w.cell_pop[best] += 1
			w.agents.cell[a] = best
		}
	}
}

// What a cell offers each person on it: its productivity, shared among the people already there.
@(private)
crowd_score :: proc(w: ^World, c: u32) -> i64 {
	return i64(w.cells[c].productivity) * 1000 / i64(w.cell_pop[c] + 1)
}

// Each market: buyers and sellers met in their order, at the market's price, until one side runs out. Money and goods
// only move between agents; the step's books count both.
resolve_markets :: proc(w: ^World) {
	for m in 0 ..< len(w.markets) {
		lo, hi := w.market_start[m], w.market_start[m + 1]
		if hi <= lo { continue }
		price := w.markets[m].price
		buyers, sellers := 0, 0
		buyer, seller := lo, lo
		for {
			for buyer < hi && w.intents[w.order[buyer]].side != .Buy { buyer += 1 }
			for seller < hi && w.intents[w.order[seller]].side != .Sell { seller += 1 }
			if buyer >= hi || seller >= hi { break }
			b, s := w.order[buyer], w.order[seller]
			bi, si := &w.intents[b], &w.intents[s]
			qty := min(bi.qty, si.qty)
			if qty == 0 { break }
			cost := i64(qty) * price / GOOD
			w.agents.goods[b] += i64(qty)
			w.agents.goods[s] -= i64(qty)
			w.agents.money[b] -= cost
			w.agents.money[s] += cost
			w.books.traded += i64(qty)
			w.books.trades += 1
			w.books.money_moved += cost
			buyers += 1
			sellers += 1
			bi.qty -= qty
			si.qty -= qty
			if bi.qty == 0 { buyer += 1 }
			if si.qty == 0 { seller += 1 }
		}
		// the price follows the scarcity: what was sold against what was asked for
		target := price
		if sellers > buyers {
			target = price - max(price / 8, 1) // a glut: cheaper
		} else if buyers > sellers {
			target = price + max(price / 8, 1) // scarcity: dearer
		}
		w.markets[m].price = clamp(price + (target - price) / 4, PRICE_BASE / 1000, PRICE_BASE / 200)
		w.markets[m].buyers = buyers
		w.markets[m].sellers = sellers
	}
}

// Each agent eats what it has, up to its hunger, then its hunger grows and its health follows: a hungry person weakens,
// a fed one mends. One pass.
eat_and_modulate :: proc(w: ^World) {
	for a in 0 ..< w.agents.count {
		need := i64(w.agents.hunger[a]) * (GOOD / EAT_PER_UNIT)
		centi := min(need, w.agents.goods[a])
		w.agents.goods[a] -= centi
		w.books.consumed += centi
		hunger := i64(w.agents.hunger[a]) - centi / (GOOD / EAT_PER_UNIT)
		hunger = min(hunger + HUNGER_PER_STEP, 100)
		w.agents.hunger[a] = u8(clamp(hunger, 0, 100))
		health := i64(w.agents.health[a])
		if w.agents.hunger[a] > STARVING {
			health -= 1
		} else if w.agents.goods[a] > 0 {
			health += 1
		}
		w.agents.health[a] = u8(clamp(health, 0, 100))
	}
}

// The one pass of the step that reads every agent for the sensors: the aggregates, the wealth histogram, and the books'
// closing totals. Then each sensor due this step. A four-lane SIMD sum of the goods and money columns was measured and
// kept out: at 1,000,000 agents it gave 21 steps/s against 37 for this loop (AVX2 wastes lanes on 64-bit integers, and
// the four scalar reads it still needs cost more than the vector loads save). The block layout stays ready for a wider
// vector, or for the GPU, when a measure says it pays.
measure :: proc(w: ^World) {
	m := &w.measures
	m^ = {}
	m.count = w.agents.count
	for a in 0 ..< w.agents.count {
		goods, money := w.agents.goods[a], w.agents.money[a]
		m.goods += goods
		m.money += money
		m.hunger += i64(w.agents.hunger[a])
		m.health += i64(w.agents.health[a])
		if w.agents.hunger[a] > STARVING { m.starving += 1 }
		m.wealth[bucket_of(money)] += 1
		m.wealth_n += 1
	}
	w.books.goods_end = m.goods
	w.books.money_end = m.money
	sensors_measure(w)
}

// log2 of a non-negative amount of money, from 0 to 63: a wealth bucket.
bucket_of :: proc(money: i64) -> int {
	if money <= 1 { return 0 }
	return 63 - int(intrinsics.count_leading_zeros(u64(money)))
}

// An exact Gini of a column, over the first `n` agents: the scratch buffer is sorted by value. Called by a Gini sensor,
// at its own rate, never at every step of a large world.
gini :: proc(w: ^World, field: Field, n: int) -> f64 {
	if n <= 1 { return 0 }
	values := w.scratch[:n]
	switch field {
	case .Money:
		for a in 0 ..< n { values[a] = w.agents.money[a] }
	case .Goods:
		for a in 0 ..< n { values[a] = w.agents.goods[a] }
	case .Hunger, .Health:
		return 0
	}
	slice.sort(values)
	sum: i64
	for v in values { sum += v }
	if sum <= 0 { return 0 }
	// G = (2 Σ i·x_i) / (n Σ x_i) − (n + 1)/n, with i from 1 and x sorted ascending
	weighted: i64
	for v, i in values { weighted += i64(i + 1) * v }
	num := 2 * f64(weighted)
	den := f64(n) * f64(sum)
	return num / den - f64(n + 1) / f64(n)
}

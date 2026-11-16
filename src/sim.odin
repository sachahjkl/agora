package agora

// The world beside the window: a thread that steps it, and the snapshot it publishes. The window copies the latest
// snapshot and never reads the world. Nothing published is proportional to the number of people, but the probe of one
// cell.

import "core:fmt"
import "core:slice"
import "core:sync"
import "core:thread"
import "core:time"
import engine "engine"

SERIES         :: 360 // the ring of the charts: one point every ten steps
SNAPSHOT_EVERY :: 2   // steps between two published snapshots

// The rate the world runs at now (for the segmented control).
current_rate :: proc(sim: ^Sim) -> int {
	sync.mutex_lock(&sim.mu)
	defer sync.mutex_unlock(&sim.mu)
	return sim.rate
}

// What the thread publishes and the window copies. The grid is in cells; the series is in steps.
Snapshot :: struct {
	step:     u64,
	seed:     u64, // what the world was founded from: the same seed, the same world
	agents:   int,
	width:    int,
	height:   int,
	people:   []u32,
	hunger:   []u32,
	money:    []i64,
	goods:    []i64,
	land:     []u16,
	cell_price: []i64,
	elevation: []u16,
	biome:    []u8,
	prices:   []i64,
	// the last report, for the counters
	mean_hunger: f64,
	starving:    f64,
	mean_health: f64,
	gini:        f64,
	trades:      u64,
	produced:    i64,
	// the charts
	series_step:   [SERIES]u64,
	series_goods:  [SERIES]f64,
	series_hunger: [SERIES]f64,
	series_gini:   [SERIES]f64,
	series_starving: [SERIES]f64,
	series_trades:   [SERIES]f64,
	series_n:      int,
	series_next:   int,
	// the most populated cells, for the viewer's list and its dots
	cities:    [CITY_SLOTS]City,
	cities_n:  int,
	price_mean: i64,
	// what the map's layers are scaled against, and who lives on which ground: computed when the world changes, not
	// when a frame is drawn
	mean_density: f64, // people per occupied cell
	mean_wealth:  f64, // money per person
	biome_people: [engine.Biome]u32,
	land_cells:   int,
	// the people of the chosen cell, and the cell itself
	probe_cell: u32,
	probe:      [PROBE_SLOTS]engine.Probe,
	probe_n:    int,
	// the world's news, newest last in the ring
	events:      [EVENT_SLOTS]Event,
	events_n:    int,
	events_next: int,
}

PROBE_SLOTS :: 24
EVENT_SLOTS :: 24

// One line of the world's news: a famine, a rush of newcomers. A fixed buffer, so that the engine thread and the window
// never share an allocation.
Event :: struct {
	step: u64,
	kind: Event_Kind,
	cell: int, // where it happened: the window flies there
	text: [72]u8,
	len:  int,
}

Event_Kind :: enum u8 {
	Famine,    // a place whose mean hunger passed STARVING
	Relief,    // a famine that ended
	Newcomers, // a place that filled
	Exodus,    // a place that emptied
}

// Steps between two events of one kind: the news says what changes, not every step of it.
EVENT_QUIET :: 12
// How far under STARVING a place's mean hunger falls before its famine is over.
FAMINE_EASE :: 8

CITY_SLOTS :: 8

City :: struct {
	x, y:   int,
	people: u32,
	hunger: f64,
	price:  i64,
	biome:  u8,
}

sim_snapshot_make :: proc(s: ^Snapshot, cells: int) {
	s.people = make([]u32, cells)
	s.hunger = make([]u32, cells)
	s.money = make([]i64, cells)
	s.goods = make([]i64, cells)
	s.land = make([]u16, cells)
	s.cell_price = make([]i64, cells)
	s.elevation = make([]u16, cells)
	s.biome = make([]u8, cells)
}

sim_snapshot_destroy :: proc(s: ^Snapshot) {
	delete(s.people)
	delete(s.hunger)
	delete(s.money)
	delete(s.goods)
	delete(s.land)
	delete(s.cell_price)
	delete(s.elevation)
	delete(s.biome)
	s^ = {}
}

Sim :: struct {
	world:  engine.World,
	thread: ^thread.Thread,
	mu:     sync.Mutex,
	// under mu
	running: bool,
	playing: bool,
	rate:    int, // steps a second; 0: as fast as the world goes
	pub:     Snapshot, // what the window copies
	work:    Snapshot, // what the thread fills, then publishes
	// the cell the window wants the people of, or -1
	want_cell: int,
	// another world the window asked for, of the same size: the thread founds it in place of this one
	want_world:    bool,
	world_options: engine.World_Options,
	// the news: the ring, and the state of the last step, to see a famine or a rush start
	events:      [EVENT_SLOTS]Event,
	events_n:    int,
	events_next: int,
	famished:    []bool, // the cells that are in a famine
	prev_people: []u32,
	prev_valid:  bool,
	last_event:  [Event_Kind]u64,
	elapsed: time.Duration,
}

// One event into the ring, its text cut to the event's buffer; none when its kind spoke less than EVENT_QUIET steps ago.
event_push :: proc(sim: ^Sim, step: u64, kind: Event_Kind, cell: int, format: string, args: ..any) {
	if sim.last_event[kind] != 0 && step - sim.last_event[kind] < EVENT_QUIET { return }
	sim.last_event[kind] = step
	e := &sim.events[sim.events_next]
	e.step = step
	e.kind = kind
	e.cell = cell
	written := fmt.bprintf(e.text[:], format, ..args)
	e.len = clamp(len(written), 0, len(e.text))
	sim.events_next = (sim.events_next + 1) % EVENT_SLOTS
	sim.events_n = min(sim.events_n + 1, EVENT_SLOTS)
}

event_text :: proc(e: ^Event) -> string { return string(e.text[:e.len]) }

// `warm`: steps the world lives before the thread starts, so that a picture of the documentation shows a world that has
// a history. The window is not open yet: nothing waits for them.
sim_start :: proc(sim: ^Sim, w: engine.World, rate: int, warm := 0) {
	sim.world = w
	sim.playing = true
	sim.want_cell = -1
	sim.rate = rate
	sim.running = true
	cells := w.width * w.height
	sim_snapshot_make(&sim.pub, cells)
	sim_snapshot_make(&sim.work, cells)
	sim.pub.width, sim.pub.height = w.width, w.height
	sim.work.width, sim.work.height = w.width, w.height
	sim.pub.prices = make([]i64, len(w.markets))
	sim.work.prices = make([]i64, len(w.markets))
	sim.famished = make([]bool, cells)
	sim.prev_people = make([]u32, cells)
	// the first picture is the world as founded
	sim_publish(sim)
	for _ in 0 ..< warm {
		engine.world_step(&sim.world)
		if sim.world.step % SNAPSHOT_EVERY == 0 { sim_publish(sim) }
	}
	sim.thread = thread.create_and_start_with_data(sim, sim_run, name = "engine")
}

sim_stop :: proc(sim: ^Sim) {
	sync.mutex_lock(&sim.mu)
	sim.running = false
	sync.mutex_unlock(&sim.mu)
	if sim.thread != nil {
		thread.join(sim.thread)
		thread.destroy(sim.thread)
		sim.thread = nil
	}
	sim_snapshot_destroy(&sim.pub)
	sim_snapshot_destroy(&sim.work)
	delete(sim.famished)
	delete(sim.prev_people)
	engine.world_destroy(&sim.world)
}

// The thread: step while playing, at the rate asked, and publish every few steps.
sim_run :: proc(user: rawptr) {
	sim := (^Sim)(user)
	for {
		sync.mutex_lock(&sim.mu)
		running, playing, rate := sim.running, sim.playing, sim.rate
		found, options := sim.want_world, sim.world_options
		if found {
			sim.want_world = false
			sim.events_n, sim.events_next = 0, 0
		}
		sync.mutex_unlock(&sim.mu)
		if !running { return }
		if found {
			// the founding is here, on the world's own thread: the window keeps drawing the old world meanwhile
			engine.world_destroy(&sim.world)
			sim.world = engine.world_make(options)
			sim.work.series_n, sim.work.series_next = 0, 0
			sim.work.gini = 0
			sim.last_event = {}
			sim.prev_valid = false
			slice.zero(sim.famished)
			sim_publish(sim)
			continue
		}
		if !playing {
			time.sleep(20 * time.Millisecond)
			continue
		}
		start := time.tick_now()
		engine.world_step(&sim.world)
		if sim.world.step % SNAPSHOT_EVERY == 0 { sim_publish(sim) }
		if rate > 0 {
			want := time.Duration(u64(1_000_000_000) / u64(rate))
			if spent := time.tick_since(start); spent < want { time.sleep(want - spent) }
		}
	}
}

// How far a place reaches, in cells: no other place is named within it.
PLACE_REACH :: 3

// True when no cell within PLACE_REACH of `c` holds more people (the lower index wins between equals).
is_peak :: proc(people: []u32, width, height, c: int) -> bool {
	x, y := c % width, c / width
	for ny in max(0, y - PLACE_REACH) ..= min(height - 1, y + PLACE_REACH) {
		for nx in max(0, x - PLACE_REACH) ..= min(width - 1, x + PLACE_REACH) {
			n := ny * width + nx
			if n == c { continue }
			if people[n] > people[c] || (people[n] == people[c] && n < c) { return false }
		}
	}
	return true
}

// The world into the published snapshot, under the lock: the map, the counters, the series.
sim_publish :: proc(sim: ^Sim) {
	w := &sim.world
	engine.cells_snapshot(w, sim.work.people, sim.work.hunger, sim.work.money, sim.work.goods)
	for c in 0 ..< len(w.cells) {
		sim.work.land[c] = w.cells[c].productivity
		sim.work.elevation[c] = w.cells[c].elevation
		sim.work.biome[c] = u8(w.cells[c].biome)
	}
	// the most populated cells, and the mean price of the markets that hold people. A cell that has a more populated
	// neighbour is a part of that neighbour's place, not a place of its own.
	sim.work.cities_n = 0
	sim.work.cities = {}
	for c in 0 ..< len(w.cells) {
		people := sim.work.people[c]
		if people == 0 { continue }
		if !is_peak(sim.work.people, w.width, w.height, c) { continue }
		city := City {
			x = c % w.width, y = c / w.width,
			people = people,
			hunger = f64(sim.work.hunger[c]) / f64(people),
			price  = w.markets[engine.market_of(w, u32(c))].price,
			biome  = u8(w.cells[c].biome),
		}
		// a small sorted insertion: at most six entries move
		slot := min(sim.work.cities_n, CITY_SLOTS - 1)
		for slot > 0 && sim.work.cities[slot - 1].people < city.people {
			sim.work.cities[slot] = sim.work.cities[slot - 1]
			slot -= 1
		}
		sim.work.cities[slot] = city
		sim.work.cities_n = min(sim.work.cities_n + 1, CITY_SLOTS)
	}
	{
		count, sum, money, people: i64
		land := 0
		sim.work.biome_people = {}
		for c in 0 ..< len(w.cells) {
			if w.cells[c].productivity > 0 { land += 1 }
			if sim.work.people[c] == 0 { continue }
			sum += w.markets[engine.market_of(w, u32(c))].price
			count += 1
			money += sim.work.money[c]
			people += i64(sim.work.people[c])
			sim.work.biome_people[w.cells[c].biome] += sim.work.people[c]
		}
		sim.work.price_mean = count > 0 ? sum / count : 0
		sim.work.mean_density = count > 0 ? f64(people) / f64(count) : 0
		sim.work.mean_wealth = people > 0 ? f64(money) / f64(people) : 0
		sim.work.land_cells = land
	}
	// the news: a famine that starts or ends, a place that fills or empties
	if sim.prev_valid {
		famine, famine_at := -1, 0.0
		relief, relief_at := -1, 100.0
		grown, grown_by := -1, 0
		left, left_by := -1, 0
		for c in 0 ..< len(w.cells) {
			people := sim.work.people[c]
			d := int(people) - int(sim.prev_people[c])
			if d > grown_by { grown_by, grown = d, c }
			if -d > left_by { left_by, left = -d, c }
			if people < 25 { continue }
			// a famine starts at STARVING and ends FAMINE_EASE under it: a place that stays near the line is one
			// famine, not a famine at every step
			now := f64(sim.work.hunger[c]) / f64(people)
			if !sim.famished[c] && now >= engine.STARVING {
				sim.famished[c] = true
				if now > famine_at { famine_at, famine = now, c }
			} else if sim.famished[c] && now < engine.STARVING - FAMINE_EASE {
				sim.famished[c] = false
				if now < relief_at { relief_at, relief = now, c }
			}
		}
		name :: proc(sim: ^Sim, c: int) -> string { return city_name(c % sim.world.width, c / sim.world.width) }
		if famine >= 0 { event_push(sim, w.step, .Famine, famine, "Famine in %s", name(sim, famine)) }
		if relief >= 0 { event_push(sim, w.step, .Relief, relief, "%s eats again", name(sim, relief)) }
		if grown >= 0 && grown_by >= 12 { event_push(sim, w.step, .Newcomers, grown, "%d people reach %s", grown_by, name(sim, grown)) }
		if left >= 0 && left_by >= 12 { event_push(sim, w.step, .Exodus, left, "%d people leave %s", left_by, name(sim, left)) }
	}
	copy(sim.prev_people, sim.work.people)
	sim.prev_valid = true
	// the chosen cell's people, asked for by the window
	sync.mutex_lock(&sim.mu)
	want := sim.want_cell
	sync.mutex_unlock(&sim.mu)
	sim.work.probe_cell = want < 0 ? 0 : u32(want)
	sim.work.probe_n = 0
	if want >= 0 { sim.work.probe_n = engine.probe_agents(w, u32(want), sim.work.probe[:]) }
	for c in 0 ..< len(w.cells) { sim.work.cell_price[c] = w.markets[engine.market_of(w, u32(c))].price }
	for m in 0 ..< len(w.markets) { sim.work.prices[m] = w.markets[m].price }
	r := engine.report(w)
	sim.work.step, sim.work.seed = w.step, w.seed
	sim.work.agents = r.agents
	sim.work.mean_hunger = r.hunger
	sim.work.starving = r.starving
	sim.work.mean_health = r.health
	sim.work.trades = r.trades
	sim.work.produced = r.produced
	// the exact Gini, off the interface's thread, at the rate of the chart
	if w.step % 10 == 0 {
		sim.work.gini = engine.gini(w, .Money, w.agents.count)
		sim.work.series_step[sim.work.series_next] = w.step
		sim.work.series_goods[sim.work.series_next] = f64(r.goods)
		sim.work.series_hunger[sim.work.series_next] = r.hunger
		sim.work.series_gini[sim.work.series_next] = sim.work.gini
		sim.work.series_starving[sim.work.series_next] = r.starving
		sim.work.series_trades[sim.work.series_next] = f64(r.trades)
		sim.work.series_next = (sim.work.series_next + 1) % SERIES
		sim.work.series_n = min(sim.work.series_n + 1, SERIES)
	}
	sync.mutex_lock(&sim.mu)
	sim.pub.step = sim.work.step
	sim.pub.agents, sim.pub.seed = sim.work.agents, sim.work.seed
	sim.pub.mean_hunger = sim.work.mean_hunger
	sim.pub.starving = sim.work.starving
	sim.pub.mean_health = sim.work.mean_health
	sim.pub.gini = sim.work.gini
	sim.pub.trades = sim.work.trades
	sim.pub.produced = sim.work.produced
	sim.pub.series_n, sim.pub.series_next = sim.work.series_n, sim.work.series_next
	sim.pub.series_step = sim.work.series_step
	sim.pub.series_goods = sim.work.series_goods
	sim.pub.series_hunger = sim.work.series_hunger
	sim.pub.series_gini = sim.work.series_gini
	sim.pub.series_starving, sim.pub.series_trades = sim.work.series_starving, sim.work.series_trades
	sim.pub.mean_density, sim.pub.mean_wealth = sim.work.mean_density, sim.work.mean_wealth
	sim.pub.biome_people, sim.pub.land_cells = sim.work.biome_people, sim.work.land_cells
	sim.pub.cities, sim.pub.cities_n, sim.pub.price_mean = sim.work.cities, sim.work.cities_n, sim.work.price_mean
	sim.pub.probe_cell, sim.pub.probe, sim.pub.probe_n = sim.work.probe_cell, sim.work.probe, sim.work.probe_n
	sim.pub.events, sim.pub.events_n, sim.pub.events_next = sim.events, sim.events_n, sim.events_next
	copy(sim.pub.people, sim.work.people)
	copy(sim.pub.hunger, sim.work.hunger)
	copy(sim.pub.money, sim.work.money)
	copy(sim.pub.goods, sim.work.goods)
	copy(sim.pub.land, sim.work.land)
	copy(sim.pub.cell_price, sim.work.cell_price)
	copy(sim.pub.elevation, sim.work.elevation)
	copy(sim.pub.biome, sim.work.biome)
	copy(sim.pub.prices, sim.work.prices)
	sync.mutex_unlock(&sim.mu)
}

// The window's copy: the latest published snapshot, under the lock.
sim_copy :: proc(sim: ^Sim, out: ^Snapshot) {
	sync.mutex_lock(&sim.mu)
	out.step, out.agents, out.seed = sim.pub.step, sim.pub.agents, sim.pub.seed
	out.mean_hunger, out.starving, out.mean_health = sim.pub.mean_hunger, sim.pub.starving, sim.pub.mean_health
	out.gini, out.trades, out.produced = sim.pub.gini, sim.pub.trades, sim.pub.produced
	out.series_n, out.series_next = sim.pub.series_n, sim.pub.series_next
	out.series_step, out.series_goods = sim.pub.series_step, sim.pub.series_goods
	out.series_hunger, out.series_gini = sim.pub.series_hunger, sim.pub.series_gini
	out.series_starving, out.series_trades = sim.pub.series_starving, sim.pub.series_trades
	out.mean_density, out.mean_wealth = sim.pub.mean_density, sim.pub.mean_wealth
	out.biome_people, out.land_cells = sim.pub.biome_people, sim.pub.land_cells
	out.cities, out.cities_n, out.price_mean = sim.pub.cities, sim.pub.cities_n, sim.pub.price_mean
	out.probe_cell, out.probe, out.probe_n = sim.pub.probe_cell, sim.pub.probe, sim.pub.probe_n
	out.events, out.events_n, out.events_next = sim.pub.events, sim.pub.events_n, sim.pub.events_next
	copy(out.people, sim.pub.people)
	copy(out.hunger, sim.pub.hunger)
	copy(out.money, sim.pub.money)
	copy(out.goods, sim.pub.goods)
	copy(out.land, sim.pub.land)
	copy(out.cell_price, sim.pub.cell_price)
	copy(out.elevation, sim.pub.elevation)
	copy(out.biome, sim.pub.biome)
	copy(out.prices, sim.pub.prices)
	sync.mutex_unlock(&sim.mu)
}

// The cell whose people the window shows (or -1 for none).
sim_choose :: proc(sim: ^Sim, cell: int) {
	sync.mutex_lock(&sim.mu)
	sim.want_cell = cell
	sync.mutex_unlock(&sim.mu)
}

sim_set :: proc(sim: ^Sim, playing: bool = true, rate: int = -1) {
	sync.mutex_lock(&sim.mu)
	sim.playing = playing
	if rate >= 0 { sim.rate = rate }
	sync.mutex_unlock(&sim.mu)
}

// Ask for another world, of the size of this one: the thread founds it before its next step.
sim_found :: proc(sim: ^Sim, seed: u64, agents: int) {
	sync.mutex_lock(&sim.mu)
	defer sync.mutex_unlock(&sim.mu)
	sim.world_options = {width = sim.pub.width, height = sim.pub.height, agents = agents, seed = seed}
	sim.want_world = true
	sim.want_cell = -1
}

sim_playing :: proc(sim: ^Sim) -> bool {
	sync.mutex_lock(&sim.mu)
	defer sync.mutex_unlock(&sim.mu)
	return sim.playing
}

package agora

// The viewer: a window over a world that runs beside it, in a thread of its own. The window never reads the world: the
// thread publishes a snapshot (the map's per-cell sums, the series, the counters) and the interface copies the latest one.
// Nothing in a frame is proportional to the number of people: the map is a grid of cells, the series a fixed ring.


import "core:fmt"
import "core:math"
import "core:sync"
import "core:thread"
import "core:strconv"
import "core:time"
import engine "engine"
import "gt:devtools"
import "gt:draw"
import "gt:font"
import "gt:host"
import "gt:lucide"
import "gt:platform"
import "gt:render"
import "gt:ui"

SERIES          :: 360 // the ring of the charts: 12 seconds at 30 steps a second
SNAPSHOT_EVERY  :: 2   // steps between two published snapshots

Layer :: enum {
	Land,
	People,
	Hunger,
	Wealth,
}

LAYER_LABELS := [4]string{"Land", "People", "Hunger", "Wealth"}
RATE_LABELS := [4]string{"×1", "×10", "×30", "×120"}
SIDE_LABELS := [4]string{"Place", "World", "News", "Charts"}

// The rate the world runs at now (for the segmented control).
current_rate :: proc(sim: ^Sim) -> int {
	sync.mutex_lock(&sim.mu)
	defer sync.mutex_unlock(&sim.mu)
	return sim.rate
}

// What the thread publishes and the window copies. The grid is in cells; the series is in steps.
Snapshot :: struct {
	step:     u64,
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
	series_n:      int,
	series_next:   int,
	// the most populated cells, for the viewer's list and its dots
	cities:    [CITY_SLOTS]City,
	cities_n:  int,
	price_mean: i64,
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
	text: [72]u8,
	len:  int,
}

// One line of the world's news, cut to the event's buffer.
Event_Text :: struct {
	text: string,
}

CITY_SLOTS :: 6

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
	// the news: the ring, and the state of the last step, to see a famine or a rush start
	events:      [EVENT_SLOTS]Event,
	events_n:    int,
	events_next: int,
	prev_hunger: []u32,
	prev_people: []u32,
	prev_valid:  bool,
	elapsed: time.Duration,
}

// One event into the ring, its text cut to the event's buffer.
event_push :: proc(sim: ^Sim, step: u64, format: string, args: ..any) {
	e := &sim.events[sim.events_next]
	e.step = step
	written := fmt.bprintf(e.text[:], format, ..args)
	e.len = clamp(len(written), 0, len(e.text))
	sim.events_next = (sim.events_next + 1) % EVENT_SLOTS
	sim.events_n = min(sim.events_n + 1, EVENT_SLOTS)
}

event_text :: proc(e: ^Event) -> string { return string(e.text[:e.len]) }

sim_start :: proc(sim: ^Sim, w: engine.World, rate: int) {
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
	sim.prev_hunger = make([]u32, cells)
	sim.prev_people = make([]u32, cells)
	// the first picture is the world as founded
	sim_publish(sim)
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
	delete(sim.prev_hunger)
	delete(sim.prev_people)
	engine.world_destroy(&sim.world)
}

// The thread: step while playing, at the rate asked, and publish every few steps.
sim_run :: proc(user: rawptr) {
	sim := (^Sim)(user)
	for {
		sync.mutex_lock(&sim.mu)
		running, playing, rate := sim.running, sim.playing, sim.rate
		sync.mutex_unlock(&sim.mu)
		if !running { return }
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

// The world into the published snapshot, under the lock: the map, the counters, the series.
sim_publish :: proc(sim: ^Sim) {
	w := &sim.world
	engine.cells_snapshot(w, sim.work.people, sim.work.hunger, sim.work.money, sim.work.goods)
	for c in 0 ..< len(w.cells) {
		sim.work.land[c] = w.cells[c].productivity
		sim.work.elevation[c] = w.cells[c].elevation
		sim.work.biome[c] = u8(w.cells[c].biome)
	}
	// the six most populated cells, and the mean price of the markets that hold people
	sim.work.cities_n = 0
	sim.work.cities = {}
	for c in 0 ..< len(w.cells) {
		people := sim.work.people[c]
		if people == 0 { continue }
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
		count: i64
		sum: i64
		for c in 0 ..< len(w.cells) {
			if sim.work.people[c] == 0 { continue }
			sum += w.markets[engine.market_of(w, u32(c))].price
			count += 1
		}
		sim.work.price_mean = count > 0 ? sum / count : 0
	}
	// the news: a famine that starts, a place that fills with newcomers
	if sim.prev_valid {
		famine, famine_at := -1, 0.0
		grown, grown_by := -1, 0
		for c in 0 ..< len(w.cells) {
			people := sim.work.people[c]
			if people < 25 { continue }
			before := f64(sim.prev_hunger[c]) / f64(max(1, sim.prev_people[c]))
			now := f64(sim.work.hunger[c]) / f64(people)
			if before < 70 && now >= 70 && now > famine_at {
				famine_at, famine = now, c
			}
			if d := int(people) - int(sim.prev_people[c]); d > grown_by {
				grown_by, grown = d, c
			}
		}
		if famine >= 0 {
			event_push(sim, w.step, "%s: a famine (%.0f hungry)", city_name(famine % w.width, famine / w.width, sim.work.biome[famine]), famine_at)
		}
		if grown >= 0 && grown_by >= 20 {
			event_push(sim, w.step, "%s: %d newcomers", city_name(grown % w.width, grown / w.width, sim.work.biome[grown]), grown_by)
		}
	}
	copy(sim.prev_hunger, sim.work.hunger)
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
	sim.work.step = w.step
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
		sim.work.series_next = (sim.work.series_next + 1) % SERIES
		sim.work.series_n = min(sim.work.series_n + 1, SERIES)
	}
	sync.mutex_lock(&sim.mu)
	sim.pub.step = sim.work.step
	sim.pub.agents = sim.work.agents
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
	out.step, out.agents = sim.pub.step, sim.pub.agents
	out.mean_hunger, out.starving, out.mean_health = sim.pub.mean_hunger, sim.pub.starving, sim.pub.mean_health
	out.gini, out.trades, out.produced = sim.pub.gini, sim.pub.trades, sim.pub.produced
	out.series_n, out.series_next = sim.pub.series_n, sim.pub.series_next
	out.series_step, out.series_goods = sim.pub.series_step, sim.pub.series_goods
	out.series_hunger, out.series_gini = sim.pub.series_hunger, sim.pub.series_gini
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

sim_playing :: proc(sim: ^Sim) -> bool {
	sync.mutex_lock(&sim.mu)
	defer sync.mutex_unlock(&sim.mu)
	return sim.playing
}

////////////////////////////////
// The window

App :: struct {
	shared:   host.Shared,
	main:     host.Host,
	sim:      Sim,
	snap:     Snapshot,
	layer:    Layer,
	zoom:     f32,
	cx, cy:   f32,
	selected_cell:   int,
	selected_person: int,
	hover_cell:      int,
	dragged:         bool,
	side:            int,
	drag_cx, drag_cy: f32,
	devtools: ^devtools.Server,
	shown:    ui.Theme_Shown,
}

// The toolkit's look, as every program of the toolkit wears it: a theme of its list, and the machined finish.
THEME :: ui.Theme_Choice{name = "Midnight", mode = .Dark, finish = .Machined, glow = 1}

Map_Draw :: struct {
	snap:  ^Snapshot,
	layer: Layer,
	zoom:  f32, // 1: the whole world; 8: a cell is eight times wider
	cx, cy: f32, // the centre of the view, in cells
	font:  font.Font_Id, // the labels of the biggest places
	font_size: f32,
	selected_cell: int,
	probe:   []engine.Probe,
	probe_n: int,
}

// The part of the world a view shows, and the size of a cell on the screen.
Map_View :: struct {
	x0, y0:  f32,
	width, height: f32,
	cell_x, cell_y: f32,
	rect: draw.Rect,
}

map_view :: proc(s: ^Snapshot, zoom, cx, cy: f32, r: draw.Rect) -> Map_View {
	z := clamp(zoom, 1, 16)
	view_w := f32(s.width) / z
	view_h := f32(s.height) / z
	v := Map_View {
		x0     = clamp(cx - view_w * 0.5, 0, f32(s.width) - view_w),
		y0     = clamp(cy - view_h * 0.5, 0, f32(s.height) - view_h),
		width  = view_w,
		height = view_h,
		rect   = r,
	}
	v.cell_x = (r.max.x - r.min.x) / view_w
	v.cell_y = (r.max.y - r.min.y) / view_h
	return v
}

// The cell under a point of the map ("-" outside it).
cell_at :: proc(v: Map_View, s: ^Snapshot, p: draw.Vec2) -> int {
	if p.x < v.rect.min.x || p.y < v.rect.min.y || p.x > v.rect.max.x || p.y > v.rect.max.y { return -1 }
	x := int(v.x0 + (p.x - v.rect.min.x) / v.cell_x)
	y := int(v.y0 + (p.y - v.rect.min.y) / v.cell_y)
	if x < 0 || y < 0 || x >= s.width || y >= s.height { return -1 }
	return y * s.width + x
}

// The map: one rectangle a cell, shaded by the layer chosen, from the layer's emptiest cell to its fullest, so that a
// quiet world still reads.
map_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Map_Draw)(user)
	s := d.snap
	if s.width == 0 || len(s.people) == 0 { return }
	r := b.rect
	v := map_view(s, d.zoom, d.cx, d.cy, r)
	x0, y0 := v.x0, v.y0
	cell_x, cell_y := v.cell_x, v.cell_y
	view_w, view_h := v.width, v.height
	cell := min(cell_x, cell_y)
	sum: f64
	occupied: int
	for c in 0 ..< s.width * s.height {
		if s.people[c] <= 0 { continue }
		sum += cell_value(s, c, d.layer if d.layer != .Land else .People)
		occupied += 1
	}
	// the scale: hunger against a fixed level (a starving world is red), the others against twice their mean, so that an
	// ordinary cell reads mid-way. The ground has its own colours.
	scale := occupied > 0 ? 2 * sum / f64(occupied) : 1
	if d.layer == .Hunger { scale = 60 }
	if scale <= 0 { scale = 1 }
	x1 := min(s.width, int(x0 + view_w + 0.999))
	y1 := min(s.height, int(y0 + view_h + 0.999))
	for y in int(y0) ..< y1 {
		for x in int(x0) ..< x1 {
			c := y * s.width + x
			colour := ground_colour(s, x, y, c)
			if d.layer != .Land && s.people[c] > 0 {
				t := f32(clamp(cell_value(s, c, d.layer) / scale, 0, 1))
				colour = draw.mix(colour, layer_colour(d.layer, t), 0.72)
			}
			px := r.min.x + (f32(x) - x0) * cell_x
			py := r.min.y + (f32(y) - y0) * cell_y
			draw.rect(dc, {{px, py}, {px + cell_x + 0.5, py + cell_y + 0.5}}, colour)
		}
	}
	// the biggest places: their dots, and their names when the view is close enough
	for i in 0 ..< s.cities_n {
		city := s.cities[i]
		px := r.min.x + (f32(city.x) - x0) * cell_x + cell_x * 0.5
		py := r.min.y + (f32(city.y) - y0) * cell_y + cell_y * 0.5
		if px < r.min.x || py < r.min.y || px > r.max.x || py > r.max.y { continue }
		radius := clamp(cell * 0.4, 1.5, 6)
		draw.rect(dc, {{px - radius, py - radius}, {px + radius, py + radius}}, draw.hex(0xFFF3D6FF), radius)
		if d.zoom >= 2.5 && d.font != 0 {
			name := city_name(city.x, city.y, city.biome)
			draw.text(dc, d.font, max(d.font_size * 1.1, 10), {px + radius + 3, py - radius - 2}, draw.hex(0xFFF3D6FF), name)
		}
	}
	// the chosen cell: a ring, and its people as dots when the view is close enough to see them
	if d.selected_cell >= 0 && d.selected_cell < s.width * s.height {
		cell := d.selected_cell
		cx := int(cell) % s.width
		cy := int(cell) / s.width
		px := r.min.x + (f32(cx) - x0) * cell_x
		py := r.min.y + (f32(cy) - y0) * cell_y
		draw.rect(dc, {{px, py}, {px + cell_x, py + cell_y}}, {}, 0, 1.5, 1, draw.hex(0xFFF3D6FF))
		if d.zoom >= 4 && d.probe_n > 0 {
			cols := 6
			rows := max(1, (d.probe_n + cols - 1) / cols)
			dot := clamp(min(cell_x, cell_y) / 12, 1.2, 4)
			for i in 0 ..< d.probe_n {
				ix := i % cols
				iy := i / cols
				gx := px + cell_x * (0.18 + 0.64 * f32(ix) / f32(cols - 1))
				gy := py + cell_y * (0.25 + 0.5 * f32(iy) / f32(max(1, rows - 1)))
				person_hunger := f32(d.probe[i].hunger) / 100
				draw.rect(dc, {{gx - dot, gy - dot}, {gx + dot, gy + dot}}, draw.mix(draw.hex(0xFFF3D6FF), draw.hex(0xF0715FFF), person_hunger), dot)
			}
		}
	}
	draw.rect(dc, r, {}, 0, 1, 1, ui.color("window border"))

	// the legend, over the map's lower left: the layer's name, and the scale's two ends
	if d.font != 0 {
		pad: f32 = 8
		box := draw.Rect{{r.min.x + 10, r.max.y - 46}, {r.min.x + 10 + 190, r.max.y - 10}}
		draw.rect(dc, box, draw.hex(0x0B0D1CEE), 6, 1, 1, draw.hex(0xFFFFFF22))
		draw.text(dc, d.font, max(10, d.font_size * 0.85), {box.min.x + pad, box.min.y + 4}, draw.hex(0xECEFF5FF), LAYER_LABELS[int(d.layer)])
		bar := draw.Rect{{box.min.x + pad, box.max.y - 18}, {box.max.x - pad, box.max.y - 10}}
		for i in 0 ..< 24 {
			t0 := f32(i) / 24
			gx0 := bar.min.x + (bar.max.x - bar.min.x) * t0
			gx1 := bar.min.x + (bar.max.x - bar.min.x) * f32(i + 1) / 24
			c := d.layer == .Land ? ground_legend(t0) : layer_colour(d.layer, t0)
			draw.rect(dc, {{gx0, bar.min.y}, {gx1 + 0.5, bar.max.y}}, c)
		}
	}
}

// The ground's colours along the legend: the sea's deep, the coast, the grass, the hills, the snow.
ground_legend :: proc(t: f32) -> draw.Color {
	if t < 0.5 { return draw.mix(draw.hex(0x0B1A2EFF), draw.hex(0x1F506EFF), t * 2) }
	if t < 0.6 { return draw.hex(0xE4EBF0FF) }
	if t < 0.75 { return draw.mix(draw.hex(0x8FA659FF), draw.hex(0x3F6B3AFF), (t - 0.6) / 0.15) }
	return draw.mix(draw.hex(0x8A8578FF), draw.hex(0xE4EBF0FF), (t - 0.75) / 0.25)
}

// A place's name, made from where it is: the same cell always has the same name.
city_name :: proc(x, y: int, biome: u8) -> string {
	first := [8]string{"Ash", "Bran", "Cor", "Dun", "El", "Fen", "Gal", "Hal"}
	second := [8]string{"mere", "ford", "wick", "ton", "holm", "dale", "bay", "reth"}
	i := (x * 7 + y * 3) % len(first)
	j := (x * 3 + y * 11) % len(second)
	return fmt.tprintf("%s%s", first[i], second[j])
}

// The biome's name, for the chosen place.
biome_name :: proc(biome: u8) -> string {
	switch engine.Biome(biome) {
	case .Ocean:
		return "sea"
	case .Ice:
		return "ice"
	case .Tundra:
		return "tundra"
	case .Desert:
		return "desert"
	case .Grass:
		return "grassland"
	case .Forest:
		return "forest"
	case .Mountain:
		return "mountain"
	}
	return "?"
}

// The price of the market a cell belongs to, as the engine thread published it.
market_price :: proc(s: ^Snapshot, cell: int) -> i64 {
	if cell < 0 || cell >= len(s.cell_price) { return 0 }
	return s.cell_price[cell]
}

// The ground of one cell: its biome's colour, its sea's depth, and the slope's light.
ground_colour :: proc(s: ^Snapshot, x, y, c: int) -> draw.Color {
	biome := engine.Biome(s.biome[c])
	height := f32(s.elevation[c]) / 65535
	colour: draw.Color
	switch biome {
	case .Ocean:
		colour = draw.mix(draw.hex(0x0B1A2EFF), draw.hex(0x1F506EFF), clamp((height - 0.25) / 0.25, 0, 1))
	case .Ice:
		colour = draw.hex(0xDDE8EEFF)
	case .Tundra:
		colour = draw.hex(0x7C8A6BFF)
	case .Desert:
		colour = draw.hex(0xC4A66AFF)
	case .Grass:
		colour = draw.hex(0x8FA659FF)
	case .Forest:
		colour = draw.hex(0x3F6B3AFF)
	case .Mountain:
		colour = height > 0.94 ? draw.hex(0xE4EBF0FF) : draw.hex(0x8A8578FF)
	}
	// the light: a slope that climbs to the north-west is bright, one that falls that way is dark
	if biome != .Ocean {
		dx, dy: f32
		if x > 0 && x + 1 < s.width {
			dx = f32(i32(s.elevation[c + 1])) - f32(i32(s.elevation[c - 1]))
		}
		if y > 0 && y + 1 < s.height {
			dy = f32(i32(s.elevation[c + s.width])) - f32(i32(s.elevation[c - s.width]))
		}
		shade := clamp(1.05 - (dx + dy) / 9000, 0.62, 1.45)
		colour = {clamp(colour.r * shade, 0, 1), clamp(colour.g * shade, 0, 1), clamp(colour.b * shade, 0, 1), colour.a}
	}
	return colour
}

cell_value :: proc(s: ^Snapshot, c: int, layer: Layer) -> f64 {
	people := f64(s.people[c])
	if layer == .Land { return f64(s.land[c]) }
	if people <= 0 { return 0 }
	switch layer {
	case .Land:
		return f64(s.land[c])
	case .People:
		return people
	case .Hunger:
		return f64(s.hunger[c]) / people
	case .Wealth:
		return f64(s.money[c]) / people
	}
	return 0
}

// The layer's colour at t in [0, 1]: dark indigo to the layer's own bright hue.
layer_colour :: proc(layer: Layer, t: f32) -> draw.Color {
	tt := clamp(t, 0, 1)
	base := draw.hex(0x10142CFF)
	switch layer {
	case .Land:
		// rock and dry hills, then the fertile valley
		if tt < 0.5 { return draw.mix(draw.hex(0x2E2C3CFF), draw.hex(0x77794CFF), tt * 2) }
		return draw.mix(draw.hex(0x77794CFF), draw.hex(0xA7D06AFF), (tt - 0.5) * 2)
	case .People:
		return draw.mix(base, draw.hex(0xF5B94AFF), tt)
	case .Hunger:
		return draw.mix(base, draw.hex(0xF0715FFF), tt)
	case .Wealth:
		return draw.mix(base, draw.hex(0x4FD1C5FF), tt)
	}
	return base
}

Chart_Draw :: struct {
	values: []f64,
	n:      int,
	accent: draw.Color,
}

// A chart of the ring's values, oldest first, scaled to its own maximum. No labels: the counters say the numbers.
chart_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Chart_Draw)(user)
	r := b.rect
	if d.n < 2 { return }
	points := make([]draw.Vec2, d.n, context.temp_allocator)
	peak: f64 = 1
	for i in 0 ..< d.n { if d.values[i] > peak { peak = d.values[i] } }
	for i in 0 ..< d.n {
		x := r.min.x + (r.max.x - r.min.x) * f32(i) / f32(d.n - 1)
		y := r.max.y - (r.max.y - r.min.y) * f32(d.values[i] / peak) * 0.92
		points[i] = {x, y}
	}
	draw.polyline(dc, points, 1.5, d.accent)
}

build :: proc(h: ^host.Host, size: host.Vec2) {
	app := (^App)(h.user)
	if ui.theme_show(&app.shared.theme, ui.THEMES[:], THEME, &app.shown, render.blend_space(&app.shared.r)) {
		platform.set_dark_title(h.win, !app.shown.light)
	}
	sim_copy(&app.sim, &app.snap)
	em := ui.font_size()
	s := &app.snap
	icons := ui.lucide_icons()

	// the keyboard: the world's own keys, wherever the pointer is
	if ui.key_press(.Space) { sim_set(&app.sim, playing = !sim_playing(&app.sim)) }
	if ui.key_press(.Equal) { app.zoom = min(app.zoom * 1.35, 16) }
	if ui.key_press(.Minus) { app.zoom = max(app.zoom / 1.35, 1) }
	if ui.key_press(.Home) { app.zoom, app.cx, app.cy = 1, 0, 0 }

	ui.next({width = ui.fill(), height = ui.fill()})
	if ui.column() {
		// the bar: the name, the world's state, the layers and the world's clock, on a surface of its own
		ui.next({width = ui.fill(), height = ui.px(em * 3.8)})
		bar := ui.build_box({.Draw_Background, .Draw_Border}, "topbar")
		if ui.parent(bar) {
		if ui.row(.Center) {
			ui.spacer(ui.px(em * 0.9))
			ui.next({width = ui.px(em * 2), height = ui.fill(), font = icons, text_align = .Center, fg = ui.color("accent")})
			ui.label(fmt.tprintf("%s###mark", lucide.GLOBE))
			ui.label("agora")
			ui.spacer(ui.px(em * 1.2))
			ui.label(fmt.tprintf("step %d · %s people · %s goods", s.step, compact(f64(s.agents)), compact(total_goods(s))))
			ui.spacer(ui.fill())
			// the layers, then the world's clock
			layer_index := int(app.layer)
			ui.next({width = ui.px(em * 20)})
			if ui.segmented("layers", LAYER_LABELS[:], &layer_index) { app.layer = Layer(layer_index) }
			ui.spacer(ui.px(em * 0.8))
			if ui.button("zoom_out", "", lucide.ZOOM_OUT, {icon_font = icons, tip = "Further"}).clicked { app.zoom = max(app.zoom / 1.35, 1) }
			if ui.button("zoom_in", "", lucide.ZOOM_IN, {icon_font = icons, tip = "Closer"}).clicked { app.zoom = min(app.zoom * 1.35, 12) }
			if ui.button("home", "", lucide.MAXIMIZE, {icon_font = icons, tip = "The whole world"}).clicked { app.zoom, app.cx, app.cy = 1, 0, 0 }
			ui.spacer(ui.px(em * 0.8))
			playing := sim_playing(&app.sim)
			if ui.button("pause", "", playing ? lucide.PAUSE : lucide.PLAY, {icon_font = icons, tip = playing ? "Pause the world" : "Let the world run", face = .Raised}).clicked {
				sim_set(&app.sim, playing = !playing)
			}
			ui.spacer(ui.px(em * 0.6))
			rates := [4]int{1, 10, 30, 120}
			rate_now := 2
			for r, i in rates { if r == current_rate(&app.sim) { rate_now = i } }
			ui.next({width = ui.px(em * 21)})
			if ui.segmented("rates", RATE_LABELS[:], &rate_now) { sim_set(&app.sim, rate = rates[rate_now]) }
			ui.spacer(ui.px(em * 0.9))
		}
		}

		ui.spacer(ui.px(em * 0.4))
		ui.next({width = ui.fill(), height = ui.fill()})
		if ui.row() {
			// the map: its layers and its view, over the map in its frame
			ui.next({width = ui.fill(), height = ui.fill()})
			if ui.column() {
				ui.spacer(ui.px(em * 0.7))
				ui.next({width = ui.fill(), height = ui.fill()})
				frame := ui.build_box({.Draw_Background, .Draw_Border}, "map_frame")
				if ui.parent(frame) {
					ui.spacer(ui.px(em * 0.25))
					ui.next({width = ui.fill(), height = ui.fill()})
					{
						md := ui.frame_new(Map_Draw)
						md.snap = s
						md.layer = app.layer
						md.zoom = app.zoom
						md.cx = app.cx
						md.cy = app.cy
						md.font = app.shared.font
						md.font_size = em
						md.selected_cell = app.selected_cell
						md.probe = s.probe[:]
						md.probe_n = s.probe_n
						ui.next({width = ui.fill(), height = ui.fill()})
						map_box := ui.custom("map", map_draw, md, {.Clickable})
						// the pointer: which cell it is over, the drag that moves the view, the wheel that zooms, and the
						// click that chooses a place
						view := map_view(s, app.zoom, app.cx, app.cy, map_box.rect)
						app.hover_cell = cell_at(view, s, ui.mouse_pos())
						sig := ui.signal(map_box)
						if sig.pressed {
							app.drag_cx, app.drag_cy = app.cx, app.cy
							app.dragged = false
						}
						if sig.dragging {
							if abs(sig.drag_delta.x) + abs(sig.drag_delta.y) > 4 { app.dragged = true }
							if app.dragged {
								app.cx = app.drag_cx - sig.drag_delta.x / view.cell_x
								app.cy = app.drag_cy - sig.drag_delta.y / view.cell_y
							}
						}
						if sig.clicked && !app.dragged && app.hover_cell >= 0 {
							app.selected_cell = app.hover_cell
							app.selected_person = -1
							app.side = 0
							sim_choose(&app.sim, app.selected_cell)
						}
						if sig.double_clicked && app.hover_cell >= 0 {
							app.cx = f32(app.hover_cell % s.width) + 0.5
							app.cy = f32(app.hover_cell / s.width) + 0.5
							app.zoom = min(app.zoom * 2.2, 12)
						}
						if sig.scrolled.y != 0 {
							app.zoom = clamp(app.zoom * math.pow(1.0035, sig.scrolled.y), 1, 16)
						}
					}
					ui.spacer(ui.px(em * 0.55))
				}
			}

			// the sidebar: one tab at a time, so that each fact has one place
			ui.next({width = ui.px(em * 27), height = ui.fill()})
			if ui.column(flags = {.View_Scroll_Y, .Clip}, id = "###panels") {
				ui.spacer(ui.px(em * 0.7))
				ui.next({width = ui.fill(), height = ui.px(em * 2.8)})
				if ui.row(.Center) {
					ui.spacer(ui.px(em * 0.7))
					ui.next({width = ui.px(em * 25.5)})
					if ui.segmented("side", SIDE_LABELS[:], &app.side) {}
					ui.spacer(ui.px(em * 0.7))
				}
				ui.spacer(ui.px(em * 0.6))

				switch app.side {
				case 0:
					// the chosen place, and the person chosen there
					if ui.card("The chosen place", lucide.MAP_PIN) {
						if app.selected_cell < 0 {
							ui.label("Click a cell of the map.")
						} else {
							cell := app.selected_cell
							x, y := cell % s.width, cell / s.width
							people := s.people[cell]
							hunger := people > 0 ? f64(s.hunger[cell]) / f64(people) : 0
							fact("Name", city_name(x, y, s.biome[cell]))
							fact("Ground", biome_name(s.biome[cell]))
							fact("At", fmt.tprintf("%d, %d", x, y))
							fact("People", fmt.tprintf("%d", people))
							fact("Hunger", fmt.tprintf("%.1f", hunger))
							fact("Price", fmt.tprintf("%d", market_price(s, cell)))
							if s.probe_n > 0 {
								ui.spacer(ui.px(em * 0.4))
								ui.hline(ui.fill())
								ui.next({width = ui.fill(), height = ui.px(em * 1.6)})
								ui.label("  The people here")
								count := min(s.probe_n, 8)
								for i in 0 ..< count {
									p := s.probe[i]
									label := fmt.tprintf("#%d  %s  hunger %.0f", p.id, compact(f64(p.money)), f64(p.hunger))
									if ui.button(fmt.tprintf("person%d", p.id), label, o = {width = ui.fill(), left = true, quiet = true, intent = app.selected_person == int(p.id) ? .Primary : .Neutral}).clicked {
										app.selected_person = int(p.id)
									}
								}
							}
						}
					}
					for i in 0 ..< s.probe_n {
						p := s.probe[i]
						if int(p.id) != app.selected_person { continue }
						ui.spacer(ui.px(em * 0.8))
						if ui.card(fmt.tprintf("Person #%d", p.id), lucide.USER) {
							fact("Money", compact(f64(p.money)))
							fact("Goods", fmt.tprintf("%.2f", f64(p.goods) / 100))
							fact("Hunger", fmt.tprintf("%d", p.hunger))
							fact("Health", fmt.tprintf("%d", p.health))
							fact("Skill", fmt.tprintf("%d", p.skill))
						}
					}

				case 1:
					// the figures of the world, then its biggest places
					if ui.card("The world", lucide.ACTIVITY) {
						ui.next({width = ui.fill(), height = ui.px(em * 0.3)})
						ui.next({width = ui.fill(), height = ui.px(em * 5.4)})
						if ui.row() {
							ui.next({width = ui.fill(), height = ui.fill()})
							if ui.column() { tile("People", compact(f64(s.agents)), "of the world") }
							ui.next({width = ui.fill(), height = ui.fill()})
							if ui.column() { tile("Hunger", fmt.tprintf("%.1f", s.mean_hunger), "of a hundred") }
						}
						ui.next({width = ui.fill(), height = ui.px(em * 5.4)})
						if ui.row() {
							ui.next({width = ui.fill(), height = ui.fill()})
							if ui.column() { tile("Starving", fmt.tprintf("%.1f%%", s.starving), "above 70") }
							ui.next({width = ui.fill(), height = ui.fill()})
							if ui.column() { tile("Gini", fmt.tprintf("%.3f", s.gini), "of money") }
						}
						ui.next({width = ui.fill(), height = ui.px(em * 0.3)})
						ui.hline(ui.fill())
						fact("Trades in the last step", fmt.tprintf("%d", s.trades))
						fact("Goods in the world", compact(total_goods(s)))
						fact("Money per person", compact(mean_money(s)))
						fact("Health", fmt.tprintf("%.1f", s.mean_health))
					}
					ui.spacer(ui.px(em * 0.8))
					if ui.card("The biggest places", lucide.BUILDING_2) {
						table_head(em, "place", "people", "hunger", "price")
						ui.hline(ui.fill())
						for i in 0 ..< s.cities_n {
							table_row(em, s.cities[i])
						}
					}

				case 2:
					// what happened: a famine that starts, a place that fills
					if ui.card("The news", lucide.NEWSPAPER) {
						if s.events_n == 0 {
							ui.label("Nothing has happened yet.")
						}
						count := min(s.events_n, 10)
						for i in 0 ..< count {
							idx := (s.events_next - 1 - i + EVENT_SLOTS * 2) % EVENT_SLOTS
							e := &s.events[idx]
							ui.next({width = ui.fill(), height = ui.px(em * 2.2)})
							if ui.row(.Center) {
								if ui.style({text_align = .Right}) {
									ui.next({width = ui.px(em * 4.5), height = ui.fill()})
									ui.label(fmt.tprintf("%d", e.step))
								}
								ui.spacer(ui.px(em * 0.6))
								ui.next({width = ui.fill(), height = ui.fill()})
								ui.label(event_text(e))
							}
						}
					}

				case 3:
					if ui.card("Over time", lucide.CHART_LINE) {
						chart_head(em, "Goods in the world", compact(total_goods(s)))
						chart(s.series_goods[:], s.series_n, s.series_next, draw.hex(0xF5B94AFF), em, "goods")
						chart_head(em, "Hunger", fmt.tprintf("%.1f", s.mean_hunger))
						chart(s.series_hunger[:], s.series_n, s.series_next, draw.hex(0xF0715FFF), em, "hunger")
						chart_head(em, "Gini of money", fmt.tprintf("%.3f", s.gini))
						chart(s.series_gini[:], s.series_n, s.series_next, draw.hex(0x4FD1C5FF), em, "gini")
					}
				}
				ui.spacer(ui.px(em * 0.8))
			}
		}

		// the foot: what the pointer does, and where it is
		ui.spacer(ui.px(em * 0.4))
		ui.next({width = ui.fill(), height = ui.px(em * 2)})
		foot := ui.build_box({.Draw_Background, .Draw_Border}, "statusbar")
		if ui.parent(foot) {
			if ui.row(.Center) {
				ui.spacer(ui.px(em * 0.9))
				ui.label("Wheel zooms · drag moves · click a place · Space pauses")
				ui.spacer(ui.fill())
				if app.hover_cell >= 0 && app.hover_cell < len(s.people) {
					ui.label(
						fmt.tprintf(
							"%s · %d, %d · %d people",
							city_name(app.hover_cell % s.width, app.hover_cell / s.width, s.biome[app.hover_cell]),
							app.hover_cell % s.width,
							app.hover_cell / s.width,
							s.people[app.hover_cell],
						),
					)
				} else {
					ui.label(fmt.tprintf("%d × %d cells", s.width, s.height))
				}
				ui.spacer(ui.px(em * 0.9))
			}
		}
	}
}

// A figure of the world's panel: its name, its value, and a word under it.
tile :: proc(name, value, note: string) {
	em := ui.font_size()
	ui.next({width = ui.fill(), height = ui.px(em * 1.6)})
	ui.label(name)
	ui.next({width = ui.fill(), height = ui.px(em * 2.5)})
	if ui.style({font_size = em * 1.9}) { ui.label(value) }
	ui.next({width = ui.fill(), height = ui.px(em * 1.3)})
	if ui.style({font_size = em * 0.85}) { ui.label(note) }
}

// A line of the world's panel: a name at the left, its value at the right.
fact :: proc(name, value: string) {
	em := ui.font_size()
	ui.next({width = ui.fill(), height = ui.px(em * 1.7)})
	if ui.row(.Center) {
		ui.next({width = ui.fill(), height = ui.fill()})
		ui.label(name)
		if ui.style({text_align = .Right}) {
			ui.next({width = ui.px(em * 9), height = ui.fill()})
			ui.label(value)
		}
	}
}

// The places' table: the columns' names, then a rule, then the rows in fixed columns.
table_head :: proc(em: f32, place, people, hunger, price: string) {
	ui.next({width = ui.fill(), height = ui.px(em * 1.8)})
	if ui.row(.Center) {
		ui.next({width = ui.fill(), height = ui.fill()})
		if ui.style({font_size = em * 0.85}) { ui.label(place) }
		if ui.style({text_align = .Right, font_size = em * 0.85}) {
			ui.next({width = ui.px(em * 5), height = ui.fill()})
			ui.label(people)
			ui.next({width = ui.px(em * 6.5), height = ui.fill()})
			ui.label(hunger)
			ui.next({width = ui.px(em * 7), height = ui.fill()})
			ui.label(price)
		}
	}
}

Hunger_Bar :: struct {
	t: f32,
}

hunger_bar :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Hunger_Bar)(user)
	r := b.rect
	h := r.max.y - r.min.y
	draw.rect(dc, r, ui.color("well"), h * 0.5)
	colour := draw.mix(draw.hex(0x6FBF73FF), draw.hex(0xF0715FFF), clamp(d.t, 0, 1))
	draw.rect(dc, {r.min, {r.min.x + max(h, (r.max.x - r.min.x) * clamp(d.t, 0, 1)), r.max.y}}, colour, h * 0.5)
}

table_row :: proc(em: f32, city: City) {
	ui.next({width = ui.fill(), height = ui.px(em * 2.2)})
	if ui.row(.Center) {
		// the place: its biome's colour, then its coordinates
		ui.next({width = ui.px(em * 0.5), height = ui.px(em * 0.5), bg = biome_colour(city.biome)})
		ui.build_box({.Draw_Background}, "")
		ui.spacer(ui.px(em * 0.5))
		ui.next({width = ui.fill(), height = ui.fill()})
		ui.label(fmt.tprintf("%d, %d", city.x, city.y))
		if ui.style({text_align = .Right}) {
			ui.next({width = ui.px(em * 5), height = ui.fill()})
			ui.label(fmt.tprintf("%d", city.people))
			ui.next({width = ui.px(em * 6.5), height = ui.fill()})
			if ui.row(.Center) {
				bar := ui.frame_new(Hunger_Bar)
				bar.t = f32(city.hunger / 100)
				ui.next({width = ui.px(em * 2.6), height = ui.px(em * 0.5)})
				ui.custom("hunger_bar", hunger_bar, bar)
				ui.spacer(ui.px(em * 0.6))
				ui.next({width = ui.fill(), height = ui.fill()})
				ui.label(fmt.tprintf("%.0f", city.hunger))
			}
			ui.next({width = ui.px(em * 7), height = ui.fill()})
			ui.label(fmt.tprintf("%d", city.price))
		}
	}
}

biome_colour :: proc(biome: u8) -> draw.Color {
	switch engine.Biome(biome) {
	case .Ocean:
		return draw.hex(0x1F506EFF)
	case .Ice:
		return draw.hex(0xDDE8EEFF)
	case .Tundra:
		return draw.hex(0x7C8A6BFF)
	case .Desert:
		return draw.hex(0xC4A66AFF)
	case .Grass:
		return draw.hex(0x8FA659FF)
	case .Forest:
		return draw.hex(0x3F6B3AFF)
	case .Mountain:
		return draw.hex(0x8A8578FF)
	}
	return draw.hex(0xFFFFFFFF)
}

// What a layer shows, in one line under its name.
layer_caption :: proc(layer: Layer) -> string {
	switch layer {
	case .Land:
		return "The ground: from the sea to the ice"
	case .People:
		return "Where the people live"
	case .Hunger:
		return "Who does not eat enough"
	case .Wealth:
		return "Who holds the money"
	}
	return ""
}

// The byte of the first `c` in `s` (-1 when it is not there).
index_byte :: proc(s: string, c: u8) -> int {
	for i in 0 ..< len(s) { if s[i] == c { return i } }
	return -1
}

mean_money :: proc(s: ^Snapshot) -> f64 {
	if s.agents == 0 { return 0 }
	total: i64
	for p in s.money { total += p }
	return f64(total) / f64(s.agents)
}

total_goods :: proc(s: ^Snapshot) -> f64 {
	total: i64
	for g in s.goods { total += g }
	return f64(total) / 100
}

// A number as a person reads a big one: 12.3M, 451k, 87.
compact :: proc(v: f64) -> string {
	if math.abs(v) >= 1e9 { return fmt.tprintf("%.2fB", v / 1e9) }
	if math.abs(v) >= 1e6 { return fmt.tprintf("%.2fM", v / 1e6) }
	if math.abs(v) >= 1e3 { return fmt.tprintf("%.1fk", v / 1e3) }
	return fmt.tprintf("%.0f", v)
}

// A large figure: its name small above, its value large under it.
stat :: proc(em: f32, name, value: string) {
	ui.spacer(ui.px(em * 0.15))
	ui.label(name)
	if ui.style({font_size = em * 1.75}) { ui.label(value) }
}

// A line of a table: the place, then the numbers, in fixed columns.
row :: proc(em: f32, place, people, hunger, price: string, header: bool) {
	ui.next({width = ui.fill(), height = ui.px(em * 1.5)})
	if ui.row(.Center) {
		ui.next({width = ui.fill(), height = ui.fill()})
		ui.label(place)
		if ui.style({text_align = .Right}) {
			ui.next({width = ui.px(em * 5), height = ui.fill()})
			ui.label(people)
			ui.next({width = ui.px(em * 4.4), height = ui.fill()})
			ui.label(hunger)
			ui.next({width = ui.px(em * 7), height = ui.fill()})
			ui.label(price)
		}
	}
}

// A chart's name and its value now, then the chart itself.
chart_head :: proc(em: f32, name, value: string) {
	ui.next({width = ui.fill(), height = ui.px(em * 1.6)})
	if ui.row(.Center) {
		ui.spacer(ui.px(em * 0.6))
		ui.next({width = ui.fill(), height = ui.fill()})
		ui.label(name)
		if ui.style({text_align = .Right}) {
			ui.next({width = ui.px(em * 7), height = ui.fill()})
			ui.label(value)
		}
		ui.spacer(ui.px(em * 0.6))
	}
}

// The biome in one letter, for the list of places.
biome_letter :: proc(biome: u8) -> string {
	switch engine.Biome(biome) {
	case .Ocean:
		return "~"
	case .Ice:
		return "*"
	case .Tundra:
		return "t"
	case .Desert:
		return "d"
	case .Grass:
		return "g"
	case .Forest:
		return "f"
	case .Mountain:
		return "^"
	}
	return "?"
}

// A chart of the ring, oldest first, in a box of its own.
chart :: proc(ring: []f64, n, next: int, accent: draw.Color, em: f32, id: string) {
	if n < 2 { return }
	values := make([]f64, n, context.temp_allocator)
	for i in 0 ..< n { values[i] = ring[(next - n + i + len(ring) * 2) % len(ring)] }
	d := ui.frame_new(Chart_Draw)
	d.values = values
	d.n = n
	d.accent = accent
	ui.next({width = ui.fill(), height = ui.px(em * 5.4)})
	ui.custom(fmt.tprintf("chart-%s", id), chart_draw, d)
}

////////////////////////////////
// Opening the window

// The viewer's entry: a world of `agents` people, the window, and the loop. `frames` >= 0: that many frames of a hidden
// window, then exit (the check that it runs); `headless`: no window of the system at all (the picture comes through the
// DevTools endpoint, or the frames are only counted).
viewer_run :: proc(agents, steps_per_second, seed: u64, frames: int, headless: bool, select: string, zoom: f32) -> int {
	app := new(App)
	defer free(app)
	app.layer = .Land
	app.side = 1
	app.zoom = clamp(zoom > 0 ? zoom : 1, 1, 16)
	app.selected_cell, app.selected_person = -1, -1
	w := engine.world_make({width = 160, height = 96, agents = int(agents), seed = seed})
	cells := w.width * w.height
	app.snap.width, app.snap.height = w.width, w.height
	sim_snapshot_make(&app.snap, cells)
	app.snap.prices = make([]i64, len(w.markets))
	defer sim_snapshot_destroy(&app.snap)

	sim_start(&app.sim, w, int(steps_per_second))
	defer sim_stop(&app.sim)

	// `--select:x,y` (a place for the picture or a demonstration) and the view that shows it
	if select != "" {
		if comma := index_byte(select, ','); comma > 0 {
			if x, xok := strconv.parse_int(select[:comma]); xok {
				if y, yok := strconv.parse_int(select[comma + 1:]); yok && x >= 0 && y >= 0 && x < w.width && y < w.height {
					app.selected_cell = y * w.width + x
					app.cx, app.cy = f32(x) + 0.5, f32(y) + 0.5
					sim_choose(&app.sim, app.selected_cell)
				}
			}
		}
	}

	if !host.host_open(&app.main, &app.shared, {title = "agora", size = {1360, 900}, headless = headless}, build, app) { return 1 }
	defer host.host_close(&app.main)
	app.main.background = ui.theme_lookup(&app.shared.theme, {}, "background")
	ui.use(&app.main.state)
	app.main.state.icon_font = ui.lucide_icons()
	platform.set_dark_title(app.main.win, true)
	app.devtools = devtools.start_from_env(app.main.win, "agora")
	defer devtools.stop(app.devtools)

	if frames >= 0 {
		for _ in 0 ..< frames {
			devtools.service(app.devtools, &app.main.state, &app.shared.r)
			host.host_frame(&app.main)
		}
		fmt.printfln("agora: %d frames, %d people, step %d", frames, app.snap.agents, app.snap.step)
		return 0
	}
	platform.show_window(app.main.win)
	for !platform.is_closed(app.main.win) {
		devtools.service(app.devtools, &app.main.state, &app.shared.r)
		host.hosts_wait({&app.main})
		host.host_frame(&app.main)
	}
	return 0
}

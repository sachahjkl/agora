package agora

// The viewer: a window over a world that runs beside it, in a thread of its own. The window never reads the world: the
// thread publishes a snapshot (the map's per-cell sums, the series, the counters) and the interface copies the latest one.
// Nothing in a frame is proportional to the number of people: the map is a grid of cells, the series a fixed ring.


import "core:fmt"
import "core:sync"
import "core:thread"
import "core:time"
import engine "engine"
import "gt:devtools"
import "gt:draw"
import "gt:host"
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

LAYER_NAMES := [Layer]string{.Land = "Land", .People = "People", .Hunger = "Hunger", .Wealth = "Wealth"}

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
}

sim_snapshot_make :: proc(s: ^Snapshot, cells: int) {
	s.people = make([]u32, cells)
	s.hunger = make([]u32, cells)
	s.money = make([]i64, cells)
	s.goods = make([]i64, cells)
	s.land = make([]u16, cells)
}

sim_snapshot_destroy :: proc(s: ^Snapshot) {
	delete(s.people)
	delete(s.hunger)
	delete(s.money)
	delete(s.goods)
	delete(s.land)
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
	elapsed: time.Duration,
}

sim_start :: proc(sim: ^Sim, w: engine.World, rate: int) {
	sim.world = w
	sim.playing = true
	sim.rate = rate
	sim.running = true
	cells := w.width * w.height
	sim_snapshot_make(&sim.pub, cells)
	sim_snapshot_make(&sim.work, cells)
	sim.pub.width, sim.pub.height = w.width, w.height
	sim.work.width, sim.work.height = w.width, w.height
	sim.pub.prices = make([]i64, len(w.markets))
	sim.work.prices = make([]i64, len(w.markets))
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
	for c in 0 ..< len(w.cells) { sim.work.land[c] = w.cells[c].productivity }
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
	copy(sim.pub.people, sim.work.people)
	copy(sim.pub.hunger, sim.work.hunger)
	copy(sim.pub.money, sim.work.money)
	copy(sim.pub.goods, sim.work.goods)
	copy(sim.pub.land, sim.work.land)
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
	copy(out.people, sim.pub.people)
	copy(out.hunger, sim.pub.hunger)
	copy(out.money, sim.pub.money)
	copy(out.goods, sim.pub.goods)
	copy(out.land, sim.pub.land)
	copy(out.prices, sim.pub.prices)
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
	devtools: ^devtools.Server,
	shown:    ui.Theme_Shown,
}

// The toolkit's look, as every program of the toolkit wears it: a theme of its list, and the machined finish.
THEME :: ui.Theme_Choice{name = "Midnight", mode = .Dark, finish = .Machined, glow = 1}

Map_Draw :: struct {
	snap:  ^Snapshot,
	layer: Layer,
}

// The map: one rectangle a cell, shaded by the layer chosen, from the layer's emptiest cell to its fullest, so that a
// quiet world still reads.
map_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Map_Draw)(user)
	s := d.snap
	if s.width == 0 || len(s.people) == 0 { return }
	r := b.rect
	cell := min((r.max.x - r.min.x) / f32(s.width), (r.max.y - r.min.y) / f32(s.height))
	sum: f64
	occupied: int
	for c in 0 ..< s.width * s.height {
		v := cell_value(s, c, d.layer)
		if s.people[c] <= 0 { continue }
		sum += v
		occupied += 1
	}
	// the scale: hunger against a fixed level (a starving world is red), land against its full range, the others against
	// twice their mean, so that an ordinary cell reads mid-way
	scale := occupied > 0 ? 2 * sum / f64(occupied) : 1
	switch d.layer {
	case .Hunger:
		scale = 60
	case .Land:
		scale = 1000
	case .People, .Wealth:
	}
	if scale <= 0 { scale = 1 }
	for y in 0 ..< s.height {
		for x in 0 ..< s.width {
			c := y * s.width + x
			t := s.people[c] > 0 || d.layer == .Land ? f32(clamp(cell_value(s, c, d.layer) / scale, 0, 1)) : 0
			colour := layer_colour(d.layer, t)
			draw.rect(dc, {{r.min.x + f32(x) * cell, r.min.y + f32(y) * cell}, {r.min.x + f32(x + 1) * cell + 0.5, r.min.y + f32(y + 1) * cell + 0.5}}, colour)
		}
	}
	draw.rect(dc, r, {}, 0, 1, 1, ui.color("window border"))
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

	ui.next({width = ui.fill(), height = ui.fill()})
	if ui.column() {
		// the title bar's line
		ui.next({width = ui.fill(), height = ui.px(em * 3)})
		if ui.row(.Center) {
			ui.spacer(ui.px(em * 0.8))
			ui.label(fmt.tprintf("agora · step %d · %d people", s.step, s.agents))
			ui.spacer(ui.fill())
			playing := sim_playing(&app.sim)
			if ui.button("pause", playing ? "Pause" : "Play", o = {intent = playing ? .Neutral : .Primary}).clicked {
				sim_set(&app.sim, playing = !playing)
			}
			for rate in ([4]int{1, 10, 30, 120}) {
				label := fmt.tprintf("×%d", rate)
				ui.spacer(ui.px(em * 0.3))
				if ui.button(fmt.tprintf("rate%d", rate), label, o = {intent = .Neutral}).clicked { sim_set(&app.sim, rate = rate) }
			}
			ui.spacer(ui.px(em * 0.8))
		}

		ui.next({width = ui.fill(), height = ui.fill()})
		if ui.row() {
			// the map, on a plate of its own, with the layers under it
			ui.next({width = ui.fill(), height = ui.fill()})
			if ui.column() {
				ui.spacer(ui.px(em * 0.7))
				ui.next({width = ui.fill(), height = ui.fill()})
				map_plate := ui.build_box({.Draw_Background}, "map_plate")
				if ui.parent(map_plate) {
					md := ui.frame_new(Map_Draw)
					md.snap = s
					md.layer = app.layer
					ui.next({width = ui.fill(), height = ui.fill()})
					ui.custom("map", map_draw, md)
				}
				ui.next({width = ui.fill(), height = ui.px(em * 2.6)})
				if ui.row(.Center) {
					ui.spacer(ui.px(em * 0.8))
					for layer in Layer {
						ui.spacer(ui.px(em * 0.4))
						if ui.button(fmt.tprintf("layer%d", int(layer)), LAYER_NAMES[layer], o = {intent = app.layer == layer ? .Primary : .Neutral}).clicked {
							app.layer = layer
						}
					}
					ui.spacer(ui.px(em * 0.8))
					ui.spacer(ui.fill())
					ui.label("twice the mean is bright")
					ui.spacer(ui.px(em * 0.8))
				}
			}

			// the counters, then the charts, each on its own plate
			ui.next({width = ui.px(em * 24), height = ui.fill()})
			if ui.column() {
				ui.spacer(ui.px(em * 0.7))
				ui.next({width = ui.fill(), height = ui.px(em * 15.5)})
				counters_plate := ui.build_box({.Draw_Background}, "counters")
				if ui.parent(counters_plate) {
					ui.spacer(ui.px(em * 0.5))
					counter(app, "Money per person", fmt.tprintf("%.0f", mean_money(s)))
					counter(app, "Goods in the world", fmt.tprintf("%.0f", total_goods(s)))
					counter(app, "Hunger (mean, 0-100)", fmt.tprintf("%.1f", s.mean_hunger))
					counter(app, "Starving", fmt.tprintf("%.1f%%", s.starving))
					counter(app, "Health (mean, 0-100)", fmt.tprintf("%.1f", s.mean_health))
					counter(app, "Gini of money", fmt.tprintf("%.3f", s.gini))
					counter(app, "Trades of the last step", fmt.tprintf("%d", s.trades))
				}
				ui.spacer(ui.px(em * 0.7))
				ui.next({width = ui.fill(), height = ui.px(em * 14.5)})
				charts_plate := ui.build_box({.Draw_Background}, "charts")
				if ui.parent(charts_plate) {
					ui.spacer(ui.px(em * 0.5))
					ui.spacer(ui.px(em * 0.3))
					ui.label("  Goods in the world")
					chart(s.series_goods[:], s.series_n, s.series_next, draw.hex(0xF5B94AFF), em, "goods")
					ui.spacer(ui.px(em * 0.3))
					ui.label("  Hunger (mean)")
					chart(s.series_hunger[:], s.series_n, s.series_next, draw.hex(0xF0715FFF), em, "hunger")
					ui.spacer(ui.px(em * 0.3))
					ui.label("  Gini of money")
					chart(s.series_gini[:], s.series_n, s.series_next, draw.hex(0x4FD1C5FF), em, "gini")
				}
				ui.spacer(ui.px(em * 0.7))
			}
		}
	}
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

counter :: proc(app: ^App, name, value: string) {
	em := ui.font_size()
	ui.next({width = ui.fill(), height = ui.px(em * 1.8)})
	if ui.row(.Center) {
		ui.spacer(ui.px(em))
		ui.label(fmt.tprintf("%s###%s", name, name))
		ui.spacer(ui.fill())
		ui.label(fmt.tprintf("%s###%sv", value, name))
		ui.spacer(ui.px(em))
	}
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
	ui.next({width = ui.fill(), height = ui.px(em * 4)})
	ui.custom(fmt.tprintf("chart-%s", id), chart_draw, d)
}

////////////////////////////////
// Opening the window

// The viewer's entry: a world of `agents` people, the window, and the loop. `frames` >= 0: that many frames of a hidden
// window, then exit (the check that it runs); `headless`: no window of the system at all (the picture comes through the
// DevTools endpoint, or the frames are only counted).
viewer_run :: proc(agents, steps_per_second, seed: u64, frames: int, headless: bool) -> int {
	app := new(App)
	defer free(app)
	app.layer = .Land
	w := engine.world_make({width = 64, height = 64, agents = int(agents), seed = seed})
	cells := w.width * w.height
	app.snap.width, app.snap.height = w.width, w.height
	sim_snapshot_make(&app.snap, cells)
	app.snap.prices = make([]i64, len(w.markets))
	defer sim_snapshot_destroy(&app.snap)

	sim_start(&app.sim, w, int(steps_per_second))
	defer sim_stop(&app.sim)

	if !host.host_open(&app.main, &app.shared, {title = "agora", size = {1280, 820}, headless = headless}, build, app) { return 1 }
	defer host.host_close(&app.main)
	app.main.background = ui.theme_lookup(&app.shared.theme, {}, "background")
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

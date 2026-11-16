package agora

// The window: a bar, the map with its tools, a sidebar of four tabs, a foot. It draws the snapshot the engine thread
// publishes (sim.odin) and never reads the world. Each fact is said once: the bar holds the world's clock and its
// headline numbers, the sidebar the details, the foot what is under the pointer.

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import engine "engine"
import "gt:devtools"
import "gt:draw"
import "gt:host"
import "gt:lucide"
import "gt:platform"
import "gt:render"
import "gt:ui"

Side :: enum {
	Place,
	World,
	News,
	Charts,
}

SIDE_LABELS := [4]string{"Place", "World", "News", "Charts"}
RATES := [4]int{1, 10, 30, 120}
RATE_LABELS := [4]string{"×1", "×10", "×30", "×120"}

// How much a notch of the wheel, a zoom button or a double click changes the zoom.
ZOOM_NOTCH :: 1.25
ZOOM_STEP  :: 1.5
ZOOM_FLY   :: 6.0
// The people of a place its table shows.
PEOPLE_SHOWN :: 10
NEWS_SHOWN   :: 14

App :: struct {
	shared:           host.Shared,
	main:             host.Host,
	sim:              Sim,
	snap:             Snapshot,
	layer:            Layer,
	side:             Side,
	zoom:             f32,
	cx, cy:           f32,
	map_rect:         draw.Rect, // where the map was drawn last: a zoom keeps the point under the pointer
	selected_cell:    int,
	selected_person:  int,
	first_person:     bool, // choose the first person of the chosen place (a picture of the documentation)
	hover_cell:       int,
	new_seed:         int, // the dialog that founds another world: its seed and its choice of PEOPLE_CHOICES
	new_people:       int,
	dragged:          bool,
	drag_cx, drag_cy: f32,
	devtools:         ^devtools.Server,
	shown:            ui.Theme_Shown,
}

// The toolkit's look, as every program of the toolkit wears it: a theme of its list, and the machined finish.
THEME :: ui.Theme_Choice{name = "Midnight", mode = .Dark, finish = .Machined, glow = 1}

build :: proc(h: ^host.Host, size: host.Vec2) {
	app := (^App)(h.user)
	if ui.theme_show(&app.shared.theme, ui.THEMES[:], THEME, &app.shown, render.blend_space(&app.shared.r)) {
		platform.set_dark_title(h.win, !app.shown.light)
	}
	sim_copy(&app.sim, &app.snap)
	s := &app.snap
	if app.first_person && app.selected_person < 0 && s.probe_n > 0 { app.selected_person = int(s.probe[0].id) }

	// the keyboard: the world's own keys, wherever the pointer is
	if ui.key_press(.Space) { sim_set(&app.sim, playing = !sim_playing(&app.sim)) }
	if ui.key_press(.Equal) { zoom_by(app, ZOOM_STEP) }
	if ui.key_press(.Minus) { zoom_by(app, 1 / ZOOM_STEP) }
	if ui.key_press(.Home) { app.zoom = 1 }
	if ui.key_press(.Escape) { select_cell(app, -1) }
	if ui.key_press(.N1) { app.layer = .Land }
	if ui.key_press(.N2) { app.layer = .People }
	if ui.key_press(.N3) { app.layer = .Hunger }
	if ui.key_press(.N4) { app.layer = .Wealth }

	ui.next({width = ui.fill(), height = ui.fill()})
	if ui.column() {
		build_bar(app)
		ui.next({width = ui.fill(), height = ui.fill()})
		if ui.row() {
			build_map(app)
			build_side(app)
		}
		build_foot(app)
	}
}

////////////////////////////////
// What the buttons and the pointer do

// The cell whose people the sidebar shows (-1: none). The engine thread is asked for them.
select_cell :: proc(app: ^App, cell: int) {
	app.selected_cell = cell
	app.selected_person = -1
	sim_choose(&app.sim, cell)
	if cell >= 0 { app.side = .Place }
}

// Choose a cell and go there, close enough to see its houses.
fly_to :: proc(app: ^App, cell: int) {
	select_cell(app, cell)
	app.cx, app.cy = f32(cell % app.snap.width) + 0.5, f32(cell / app.snap.width) + 0.5
	app.zoom = max(app.zoom, ZOOM_FLY)
}

// The zoom times `factor`, the cell at `p` staying under `p`.
zoom_at :: proc(app: ^App, p: draw.Vec2, factor: f32) {
	r := app.map_rect
	if r.max.x <= r.min.x { return }
	before := map_view(&app.snap, app.zoom, app.cx, app.cy, r)
	wx, wy := before.x0 + (p.x - r.min.x) / before.cell, before.y0 + (p.y - r.min.y) / before.cell
	app.zoom = clamp(app.zoom * factor, 1, ZOOM_MAX)
	after := map_view(&app.snap, app.zoom, app.cx, app.cy, r)
	app.cx = wx - (p.x - r.min.x) / after.cell + after.vw * 0.5
	app.cy = wy - (p.y - r.min.y) / after.cell + after.vh * 0.5
}

// The zoom times `factor`, about the middle of the map.
zoom_by :: proc(app: ^App, factor: f32) {
	zoom_at(app, (app.map_rect.min + app.map_rect.max) * 0.5, factor)
}

////////////////////////////////
// The bar

build_bar :: proc(app: ^App) {
	s := &app.snap
	em := ui.font_size()
	icons := ui.lucide_icons()
	ui.next({width = ui.fill(), height = ui.px(em * 3.4)})
	if ui.tags("bar") {
		if ui.row(.Center, {.Draw_Background}, "###bar") {
			ui.spacer(ui.px(em * 0.9))
			ui.icon(lucide.GLOBE, em * 1.6, ui.color("accent"), icons)
			ui.spacer(ui.px(em * 0.2))
			if ui.style({font_size = em * 1.15}) { ui.label("agora") }
			ui.spacer(ui.px(em * 1.4))
			bar_figure("Step", fmt.tprintf("%d", s.step))
			bar_figure("People", compact(f64(s.agents)))
			bar_figure("Starving", fmt.tprintf("%.1f%%", s.starving))
			bar_figure("Trades", compact(f64(s.trades)))
			ui.spacer(ui.fill())
			if ui.tags("weak") { ui.label(fmt.tprintf("Seed %d###seed", s.seed)) }
			ui.spacer(ui.px(em * 0.7))
			if ui.button("new_world", "New world", lucide.DICES, {icon_font = icons, tip = "Found another world"}).clicked {
				app.new_seed = int(s.seed) + 1
				ui.view_open(ui.views(), NEW_WORLD_VIEW, app)
			}
			ui.spacer(ui.px(em * 0.6))
			playing := sim_playing(&app.sim)
			if ui.button("play", playing ? "Pause" : "Run", playing ? lucide.PAUSE : lucide.PLAY, {icon_font = icons, intent = playing ? .Neutral : .Primary, tip = "Space"}).clicked {
				sim_set(&app.sim, playing = !playing)
			}
			ui.spacer(ui.px(em * 0.6))
			// (a rate asked on the command line can be none of the four: the nearest one is shown)
			rate, now := 0, current_rate(&app.sim)
			for r, i in RATES { if abs(r - now) < abs(RATES[rate] - now) { rate = i } }
			tips := [4]string{"1 step a second", "10 steps a second", "30 steps a second", "120 steps a second"}
			if ui.segmented("rates", RATE_LABELS[:], &rate, tips[:]) { sim_set(&app.sim, playing = playing, rate = RATES[rate]) }
			ui.spacer(ui.px(em * 0.9))
		}
	}
	ui.hline(ui.fill())
}

// A headline number of the bar: its name, weak, then its value.
bar_figure :: proc(name, value: string) {
	em := ui.font_size()
	if ui.tags("weak") { ui.label(fmt.tprintf("%s###bar_name_%s", name, name)) }
	ui.label(fmt.tprintf("%s###bar_%s", value, name))
	ui.spacer(ui.px(em * 0.9))
}

////////////////////////////////
// The dialog that founds another world

NEW_WORLD_VIEW :: "new_world"
PEOPLE_CHOICES := [4]int{50_000, 200_000, 500_000, 1_000_000}
PEOPLE_LABELS := [4]string{"50k", "200k", "500k", "1M"}

new_world_view :: proc(v: ^ui.View, app: ^App) {
	em := ui.font_size()
	if ui.dialog_body("new_world_body") {
		if ui.form_row("Seed") { ui.number("###new_seed", &app.new_seed, lo = 1, hi = 999_999) }
		if ui.form_row("People") { ui.segmented("###new_people", PEOPLE_LABELS[:], &app.new_people) }
		ui.spacer(ui.px(em * 0.5))
		if ui.tags("weak") { ui.label("The same seed always founds the same world.") }
	}
	if ui.dialog_buttons("new_world_buttons") {
		if ui.button("new_world_cancel", "Cancel", lucide.X).clicked { ui.view_end(v, ui.VIEW_CANCELLED) }
		if ui.button("new_world_found", "Found it", lucide.EARTH, {intent = .Primary}).clicked {
			sim_found(&app.sim, u64(app.new_seed), PEOPLE_CHOICES[app.new_people])
			select_cell(app, -1)
			app.zoom, app.side = 1, .World
			ui.view_end(v, 0)
		}
	}
}

////////////////////////////////
// The map and its tools

build_map :: proc(app: ^App) {
	s := &app.snap
	em := ui.font_size()
	icons := ui.lucide_icons()
	ui.next({width = ui.fill(), height = ui.fill()})
	if ui.column() {
		ui.spacer(ui.px(em * 0.7))
		ui.next({width = ui.fill(), height = ui.px(em * 2.4)})
		if ui.row(.Center) {
			ui.spacer(ui.px(em * 0.8))
			layer := int(app.layer)
			if ui.segmented("layers", LAYER_LABELS[:], &layer) { app.layer = Layer(layer) }
			ui.spacer(ui.fill())
			if ui.button("zoom_out", "", lucide.ZOOM_OUT, {icon_font = icons, tip = "Further (-)", disabled = app.zoom <= 1}).clicked { zoom_by(app, 1 / ZOOM_STEP) }
			ui.next({width = ui.px(em * 3.6), text_align = .Center})
			if ui.tags("weak") { ui.label(fmt.tprintf("×%.1f###zoom", app.zoom)) }
			if ui.button("zoom_in", "", lucide.ZOOM_IN, {icon_font = icons, tip = "Closer (=)", disabled = app.zoom >= ZOOM_MAX}).clicked { zoom_by(app, ZOOM_STEP) }
			ui.spacer(ui.px(em * 0.4))
			if ui.button("whole", "Whole world", lucide.MAXIMIZE, {icon_font = icons, tip = "Home", disabled = app.zoom <= 1}).clicked { app.zoom = 1 }
			ui.spacer(ui.px(em * 0.2))
		}
		ui.spacer(ui.px(em * 0.6))
		ui.next({width = ui.fill(), height = ui.fill()})
		if ui.row() {
			ui.spacer(ui.px(em * 0.8))
			ui.next({width = ui.fill(), height = ui.fill(), radius = em * 0.45})
			if ui.well("###map_well") {
				d := ui.frame_new(Map_Draw)
				d^ = {
					snap = s, layer = app.layer, zoom = app.zoom, cx = app.cx, cy = app.cy,
					font = app.shared.font, font_size = em,
					selected_cell = app.selected_cell, hover_cell = app.hover_cell, selected_person = app.selected_person,
					probe = s.probe[:], probe_n = s.probe_n,
				}
				ui.next({width = ui.fill(), height = ui.fill()})
				box := ui.custom("###map", map_draw, d, {.Clickable, .Scroll_Self})
				map_input(app, box)
			}
			ui.spacer(ui.px(em * 0.2))
		}
		ui.spacer(ui.px(em * 0.8))
	}
}

// The pointer on the map: the cell it is over, the wheel that zooms about it, the drag that moves the view, the click
// that chooses a place, the double click that goes there.
map_input :: proc(app: ^App, box: ^ui.Box) {
	s := &app.snap
	// (the rectangle map_draw draws in: a pixel inside the box)
	app.map_rect = {box.rect.min + {1, 1}, box.rect.max - {1, 1}}
	view := map_view(s, app.zoom, app.cx, app.cy, app.map_rect)
	sig := ui.signal(box)
	app.hover_cell = sig.hovering ? cell_at(view, s, ui.mouse_pos()) : -1
	if sig.scrolled.y != 0 { zoom_at(app, ui.mouse_pos(), math.pow(ZOOM_NOTCH, -sig.scrolled.y)) }
	if sig.pressed {
		app.drag_cx, app.drag_cy = map_centre(view)
		app.dragged = false
	}
	if sig.dragging {
		if abs(sig.drag_delta.x) + abs(sig.drag_delta.y) > 4 { app.dragged = true }
		if app.dragged {
			app.cx = app.drag_cx - sig.drag_delta.x / view.cell
			app.cy = app.drag_cy - sig.drag_delta.y / view.cell
		}
	}
	if sig.double_clicked && app.hover_cell >= 0 {
		fly_to(app, app.hover_cell)
	} else if sig.clicked && !app.dragged && app.hover_cell >= 0 {
		select_cell(app, app.hover_cell)
	}
}

////////////////////////////////
// The sidebar

build_side :: proc(app: ^App) {
	em := ui.font_size()
	ui.next({width = ui.px(em * 28), height = ui.fill()})
	if ui.column() {
		ui.spacer(ui.px(em * 0.7))
		ui.next({width = ui.fill(), height = ui.px(em * 2.4)})
		if ui.row(.Center) {
			ui.spacer(ui.px(em * 0.6))
			side := int(app.side)
			ui.next({width = ui.fill()})
			if ui.segmented("side", SIDE_LABELS[:], &side) { app.side = Side(side) }
			ui.spacer(ui.px(em * 0.9))
		}
		ui.spacer(ui.px(em * 0.6))
		ui.next({width = ui.fill(), height = ui.fill()})
		if ui.column(flags = {.View_Scroll_Y, .Clip}, id = "###side_scroll") {
			ui.next({width = ui.fill(), height = ui.children_sum()})
			if ui.row() {
				ui.spacer(ui.px(em * 0.6))
				ui.next({width = ui.fill(), height = ui.children_sum()})
				if ui.column() {
					switch app.side {
					case .Place:
						side_place(app)
					case .World:
						side_world(app)
					case .News:
						side_news(app)
					case .Charts:
						side_charts(app)
					}
				}
				ui.spacer(ui.px(em * 0.9))
			}
		}
	}
}

side_place :: proc(app: ^App) {
	s := &app.snap
	em := ui.font_size()
	if app.selected_cell < 0 || app.selected_cell >= len(s.people) {
		if ui.card("No place chosen", lucide.MAP_PIN) {
			if ui.tags("weak") {
				ui.label("Click a cell of the map to see who lives there.")
				ui.label("A double click goes to it.")
			}
		}
		return
	}
	cell := app.selected_cell
	x, y := cell % s.width, cell / s.width
	people := s.people[cell]
	if ui.card(city_name(x, y), lucide.MAP_PIN) {
		ui.next({width = ui.fill(), height = ui.px(em * 1.6)})
		if ui.row(.Center) {
			swatch(s.biome[cell])
			if ui.tags("weak") { ui.label(fmt.tprintf("%s · %d, %d###where", biome_name(s.biome[cell]), x, y)) }
		}
		if people == 0 {
			ui.spacer(ui.px(em * 0.4))
			if ui.tags("weak") { ui.label(s.land[cell] == 0 ? "Nobody can live here." : "Nobody lives here.") }
		} else {
			ui.spacer(ui.px(em * 0.5))
			tiles(
				{"People", fmt.tprintf("%d", people), fmt.tprintf("%.1f× the mean", f64(people) / max(s.mean_density, 1))},
				{"Hunger", fmt.tprintf("%.0f", f64(s.hunger[cell]) / f64(people)), "of a hundred"},
			)
			tiles(
				{"Food price", fmt.tprintf("%d", market_price(s, cell)), fmt.tprintf("the world's: %d", s.price_mean)},
				{"Land", fmt.tprintf("%d", s.land[cell]), "of a thousand"},
			)
			ui.hline(ui.fill())
			fact("Money each", compact(f64(s.money[cell]) / f64(people)))
			fact("Food in store", fmt.tprintf("%.1f meals each", f64(s.goods[cell]) / engine.GOOD / f64(people)))
		}
	}
	if people == 0 { return }
	if ui.card("Who lives here", lucide.USERS) {
		if s.probe_cell != u32(cell) || s.probe_n == 0 {
			if ui.tags("weak") { ui.label("Asking the world…") }
		} else {
			table_head({"person", "money", "food", "hunger"})
			shown := min(s.probe_n, PEOPLE_SHOWN)
			for i in 0 ..< shown {
				p := s.probe[i]
				if person_row(p, app.selected_person == int(p.id)) { app.selected_person = int(p.id) }
			}
			if int(people) > shown {
				ui.spacer(ui.px(em * 0.3))
				if ui.tags("weak") { ui.label(fmt.tprintf("and %d more###more", int(people) - shown)) }
			}
		}
	}
	for i in 0 ..< s.probe_n {
		p := s.probe[i]
		if int(p.id) != app.selected_person || s.probe_cell != u32(cell) { continue }
		if ui.card(fmt.tprintf("Person %d", p.id), lucide.USER) {
			gauge("Hunger", f32(p.hunger) / 100, fmt.tprintf("%d", p.hunger), f32(engine.STARVING) / 100)
			gauge("Health", f32(p.health) / 100, fmt.tprintf("%d", p.health))
			gauge("Skill", f32(p.skill) / 150, fmt.tprintf("%d%%", p.skill))
			ui.spacer(ui.px(em * 0.3))
			ui.hline(ui.fill())
			fact("Money", compact(f64(p.money)))
			fact("Food in store", fmt.tprintf("%.1f meals", f64(p.goods) / engine.GOOD))
		}
	}
}

side_world :: proc(app: ^App) {
	s := &app.snap
	em := ui.font_size()
	if ui.card("The world", lucide.ACTIVITY) {
		tiles(
			{"Hunger", fmt.tprintf("%.1f", s.mean_hunger), "of a hundred"},
			{"Health", fmt.tprintf("%.1f", s.mean_health), "of a hundred"},
		)
		tiles(
			{"Money each", compact(s.mean_wealth), fmt.tprintf("Gini %.3f", s.gini)},
			{"Food in store", compact(total_goods(s)), fmt.tprintf("%.1f meals each", total_goods(s) / f64(max(s.agents, 1)))},
		)
		ui.hline(ui.fill())
		fact("Land", fmt.tprintf("%d of %d cells", s.land_cells, s.width * s.height))
		fact("Food price", fmt.tprintf("%d", s.price_mean))
	}
	if ui.card("Where people live", lucide.TREE_PINE) {
		biomes := BIOMES_SHOWN
		for b in biomes {
			if s.biome_people[b] == 0 { continue }
			share := f32(s.biome_people[b]) / f32(max(s.agents, 1))
			name := biome_name(u8(b))
			ui.next({width = ui.fill(), height = ui.px(em * 1.8)})
			if ui.row(.Center, id = fmt.tprintf("###biome_%s", name)) {
				swatch(u8(b))
				ui.next({width = ui.px(em * 6)})
				ui.label(name)
				ui.next({width = ui.fill(), height = ui.px(em * 0.5)})
				ui.meter_bar("###share", share)
				ui.next({width = ui.px(em * 3.6), text_align = .Right})
				ui.label(fmt.tprintf("%.0f%%###pct", share * 100))
			}
		}
	}
	if ui.card("The biggest places", lucide.BUILDING_2) {
		table_head({"place", "people", "price", "hunger"})
		for i in 0 ..< s.cities_n {
			city := s.cities[i]
			if city_row(city) { fly_to(app, city.y * s.width + city.x) }
		}
	}
}

side_news :: proc(app: ^App) {
	s := &app.snap
	em := ui.font_size()
	if ui.card("The news", lucide.NEWSPAPER) {
		if s.events_n == 0 {
			if ui.tags("weak") { ui.label("Nothing has happened yet.") }
		}
		for i in 0 ..< min(s.events_n, NEWS_SHOWN) {
			e := &s.events[(s.events_next - 1 - i + EVENT_SLOTS * 2) % EVENT_SLOTS]
			intent := ui.Intent.Info
			switch e.kind {
			case .Famine:
				intent = .Danger
			case .Relief:
				intent = .Success
			case .Newcomers:
				intent = .Info
			case .Exodus:
				intent = .Warning
			}
			if ui.tags("list_row") {
				ui.next({width = ui.fill(), height = ui.px(em * 2.1), radius = em * 0.3})
				if ui.row(.Center, {.Clickable, .Draw_Hot_Effects}, fmt.tprintf("###news_%d", i)) {
					if ui.signal(ui.parent_box()).clicked { fly_to(app, e.cell) }
					ui.spacer(ui.px(em * 0.5))
					ui.dot("###kind", em * 0.55, intent)
					ui.spacer(ui.px(em * 0.4))
					ui.next({width = ui.fill()})
					ui.label(fmt.tprintf("%s###text", event_text(e)))
					ui.next({width = ui.px(em * 4.2), text_align = .Right})
					if ui.tags("weak") { ui.label(fmt.tprintf("%d###step", e.step)) }
					ui.spacer(ui.px(em * 0.3))
				}
			}
		}
	}
}

side_charts :: proc(app: ^App) {
	s := &app.snap
	if ui.card("Over time", lucide.CHART_LINE) {
		chart("Hunger", fmt.tprintf("%.1f", s.mean_hunger), s.series_hunger[:], s, draw.hex(MAP_CORAL), 100)
		chart("Starving", fmt.tprintf("%.1f%%", s.starving), s.series_starving[:], s, ui.hue_color(.Red))
		chart("Trades a step", compact(f64(s.trades)), s.series_trades[:], s, draw.hex(MAP_TEAL))
		chart("Food in store", compact(total_goods(s)), s.series_goods[:], s, draw.hex(MAP_GOLD))
	}
}

////////////////////////////////
// The parts of the panels

Tile :: struct {
	name, value, note: string,
}

// Two figures side by side: each a name, a large value and a word under it.
tiles :: proc(a, b: Tile) {
	em := ui.font_size()
	ui.next({width = ui.fill(), height = ui.px(em * 5.6)})
	if ui.row(id = fmt.tprintf("###tiles_%s", a.name)) {
		for t in ([2]Tile{a, b}) {
			ui.next({width = ui.fill(), height = ui.fill()})
			if ui.column(id = fmt.tprintf("###tile_%s", t.name)) {
				ui.next({width = ui.fill(), height = ui.px(em * 1.5)})
				if ui.tags("weak") { ui.label(t.name) }
				ui.next({width = ui.fill(), height = ui.px(em * 2.5), font_size = em * 1.8})
				ui.label(fmt.tprintf("%s###value", t.value))
				ui.next({width = ui.fill(), height = ui.px(em * 1.3), font_size = em * 0.85})
				if ui.tags("weak") { ui.label(fmt.tprintf("%s###note", t.note)) }
			}
		}
	}
}

// A line of a panel: a name at the left, weak, its value at the right.
fact :: proc(name, value: string) {
	em := ui.font_size()
	ui.next({width = ui.fill(), height = ui.px(em * 1.8)})
	if ui.row(.Center, id = fmt.tprintf("###fact_%s", name)) {
		ui.next({width = ui.fill()})
		if ui.tags("weak") { ui.label(name) }
		ui.next({text_align = .Right})
		ui.label(fmt.tprintf("%s###value", value))
	}
}

// A level from 0 to 1 as a bar, with its name and its value; past `alert` the bar says so.
gauge :: proc(name: string, level: f32, value: string, alert: f32 = 2) {
	em := ui.font_size()
	ui.next({width = ui.fill(), height = ui.px(em * 1.9)})
	if ui.row(.Center, id = fmt.tprintf("###gauge_%s", name)) {
		ui.next({width = ui.px(em * 5)})
		if ui.tags("weak") { ui.label(name) }
		ui.next({width = ui.fill(), height = ui.px(em * 0.5)})
		ui.meter_bar("###bar", clamp(level, 0, 1), alert)
		ui.next({width = ui.px(em * 4), text_align = .Right})
		ui.label(fmt.tprintf("%s###value", value))
	}
}

// A small square of a ground's colour, then a little room.
swatch :: proc(biome: u8) {
	em := ui.font_size()
	ui.next({width = ui.px(em * 0.7), height = ui.px(em * 0.7), bg = biome_colour(biome), radius = em * 0.15})
	ui.build_box({.Draw_Background}, "###swatch")
	ui.spacer(ui.px(em * 0.5))
}

// The widths of a table's three columns of numbers, in ems; the first column takes the rest.
TABLE_COLUMNS := [3]f32{3.8, 3.6, 5.6}

table_head :: proc(names: [4]string) {
	em := ui.font_size()
	ui.next({width = ui.fill(), height = ui.px(em * 1.7)})
	if ui.row(.Center, id = "###table_head") {
		if ui.style({font_size = em * 0.85}) {
			if ui.tags("weak") {
				ui.spacer(ui.px(em * 0.5))
				ui.next({width = ui.fill()})
				ui.label(names[0])
				for w, i in TABLE_COLUMNS {
					ui.next({width = ui.px(em * w), text_align = .Right})
					ui.label(names[i + 1])
				}
				ui.spacer(ui.px(em * 0.5))
			}
		}
	}
	ui.hline(ui.fill())
}

// The last cell of a table's row: a hunger, as a number and a small bar.
hunger_cell :: proc(hunger: f32) {
	em := ui.font_size()
	ui.next({width = ui.px(em * TABLE_COLUMNS[2]), height = ui.fill()})
	if ui.row(.Center, id = "###hunger") {
		ui.spacer(ui.fill())
		ui.next({width = ui.px(em * 2.6), height = ui.px(em * 0.45)})
		ui.meter_bar("###bar", clamp(hunger / 100, 0, 1), f32(engine.STARVING) / 100)
		ui.next({width = ui.px(em * 2.4), text_align = .Right})
		ui.label(fmt.tprintf("%.0f###value", hunger))
	}
}

// A person of the chosen place; true when it is clicked.
person_row :: proc(p: engine.Probe, chosen: bool) -> (clicked: bool) {
	em := ui.font_size()
	if ui.tags("list_row") {
		ui.next({width = ui.fill(), height = ui.px(em * 2.1), radius = em * 0.3, bg = chosen ? ui.color("selected background") : nil})
		if ui.row(.Center, {.Clickable, .Draw_Hot_Effects, .Draw_Background}, fmt.tprintf("###person_%d", p.id)) {
			clicked = ui.signal(ui.parent_box()).clicked
			ui.spacer(ui.px(em * 0.5))
			ui.next({width = ui.fill()})
			ui.label(fmt.tprintf("%d###id", p.id))
			ui.next({width = ui.px(em * TABLE_COLUMNS[0]), text_align = .Right})
			ui.label(fmt.tprintf("%s###money", compact(f64(p.money))))
			ui.next({width = ui.px(em * TABLE_COLUMNS[1]), text_align = .Right})
			ui.label(fmt.tprintf("%.1f###food", f64(p.goods) / engine.GOOD))
			hunger_cell(f32(p.hunger))
			ui.spacer(ui.px(em * 0.5))
		}
	}
	return
}

// One of the biggest places; true when it is clicked.
city_row :: proc(city: City) -> (clicked: bool) {
	em := ui.font_size()
	if ui.tags("list_row") {
		ui.next({width = ui.fill(), height = ui.px(em * 2.1), radius = em * 0.3})
		if ui.row(.Center, {.Clickable, .Draw_Hot_Effects}, fmt.tprintf("###city_%d_%d", city.x, city.y)) {
			clicked = ui.signal(ui.parent_box()).clicked
			ui.spacer(ui.px(em * 0.5))
			swatch(city.biome)
			ui.next({width = ui.fill()})
			ui.label(fmt.tprintf("%s###name", city_name(city.x, city.y)))
			ui.next({width = ui.px(em * TABLE_COLUMNS[0]), text_align = .Right})
			ui.label(fmt.tprintf("%d###people", city.people))
			ui.next({width = ui.px(em * TABLE_COLUMNS[1]), text_align = .Right})
			ui.label(fmt.tprintf("%d###price", city.price))
			hunger_cell(f32(city.hunger))
			ui.spacer(ui.px(em * 0.5))
		}
	}
	return
}

// A chart of a ring of the snapshot: its name and its value now, then the toolkit's graph. `top`: the value at the top
// of the graph (0: a round value above the largest shown).
chart :: proc(name, value: string, ring: []f64, s: ^Snapshot, colour: draw.Color, top: f32 = 0) {
	em := ui.font_size()
	fact(name, value)
	values := make([]f32, s.series_n, context.temp_allocator)
	for i in 0 ..< s.series_n { values[i] = f32(ring[(s.series_next - s.series_n + i + len(ring) * 2) % len(ring)]) }
	ui.next({width = ui.fill(), height = ui.px(em * 6)})
	ui.line_graph(fmt.tprintf("###chart_%s", name), {{values, colour}}, {top = top, grid = true, points = max(s.series_n, 2), columns = 6, rows = 3})
	ui.spacer(ui.px(em * 0.7))
}

////////////////////////////////
// The foot

build_foot :: proc(app: ^App) {
	s := &app.snap
	em := ui.font_size()
	ui.hline(ui.fill())
	ui.next({width = ui.fill(), height = ui.px(em * 2.1)})
	if ui.tags("bar") {
		if ui.row(.Center, {.Draw_Background}, "###foot") {
			if ui.style({font_size = em * 0.9}) {
				ui.spacer(ui.px(em * 0.9))
				if ui.tags("weak") {
					foot_key("Wheel", "zoom")
					foot_key("Drag", "move")
					foot_key("Click", "choose")
					foot_key("Double click", "go there")
					foot_key("Space", "pause")
				}
				ui.spacer(ui.fill())
				if c := app.hover_cell; c >= 0 && c < len(s.people) {
					x, y := c % s.width, c / s.width
					text := fmt.tprintf("%s · %s · %d, %d", city_name(x, y), biome_name(s.biome[c]), x, y)
					if s.people[c] > 0 { text = fmt.tprintf("%s · %d people", text, s.people[c]) }
					ui.label(fmt.tprintf("%s###under", text))
				}
				ui.spacer(ui.px(em * 0.9))
			}
		}
	}
}

// What a gesture does: the gesture as a key, then the word.
foot_key :: proc(key, does: string) {
	em := ui.font_size()
	ui.kbd(key)
	ui.label(fmt.tprintf("%s###does_%s", does, key))
	ui.spacer(ui.px(em * 0.8))
}

////////////////////////////////
// Numbers

// The price of the market a cell belongs to, as the engine thread published it.
market_price :: proc(s: ^Snapshot, cell: int) -> i64 {
	if cell < 0 || cell >= len(s.cell_price) { return 0 }
	return s.cell_price[cell]
}

// The food of the world, in meals.
total_goods :: proc(s: ^Snapshot) -> f64 {
	total: i64
	for g in s.goods { total += g }
	return f64(total) / engine.GOOD
}

// A number as a person reads a big one: 12.3M, 451k, 87.
compact :: proc(v: f64) -> string {
	if math.abs(v) >= 1e9 { return fmt.tprintf("%.2fB", v / 1e9) }
	if math.abs(v) >= 1e6 { return fmt.tprintf("%.2fM", v / 1e6) }
	if math.abs(v) >= 1e4 { return fmt.tprintf("%.0fk", v / 1e3) }
	if math.abs(v) >= 1e3 { return fmt.tprintf("%.1fk", v / 1e3) }
	return fmt.tprintf("%.0f", v)
}

////////////////////////////////
// Opening the window

// The viewer's entry: a world of people, the window, and the loop. `o.frames` >= 0: that many frames of a hidden window,
// then exit (the check that it runs); `o.headless`: no window of the system at all (the picture comes through the
// DevTools endpoint, or the frames are only counted).
viewer_run :: proc(o: ^Options) -> int {
	app := new(App)
	defer free(app)
	app.layer = Layer(clamp(o.layer, 0, len(Layer) - 1))
	app.side = Side(clamp(o.side, 0, len(Side) - 1))
	app.zoom = clamp(o.zoom > 0 ? o.zoom : 1, 1, ZOOM_MAX)
	app.selected_cell, app.selected_person, app.hover_cell = -1, -1, -1
	app.first_person = o.person
	w := engine.world_make({width = 160, height = 96, agents = o.agents, seed = o.seed})
	cells := w.width * w.height
	app.snap.width, app.snap.height = w.width, w.height
	app.cx, app.cy = f32(w.width) * 0.5, f32(w.height) * 0.5
	sim_snapshot_make(&app.snap, cells)
	app.snap.prices = make([]i64, len(w.markets))
	defer sim_snapshot_destroy(&app.snap)

	sim_start(&app.sim, w, o.rate, max(o.warm, 0))
	defer sim_stop(&app.sim)

	// `--select:x,y`: a place chosen from the start, and the view on it
	if comma := strings.index_byte(o.select, ','); comma > 0 {
		x, xok := strconv.parse_int(o.select[:comma])
		y, yok := strconv.parse_int(o.select[comma + 1:])
		if xok && yok && x >= 0 && y >= 0 && x < w.width && y < w.height {
			side := app.side
			select_cell(app, y * w.width + x)
			app.side = side
			app.cx, app.cy = f32(x) + 0.5, f32(y) + 0.5
		}
	}

	if !host.host_open(&app.main, &app.shared, {title = "agora", size = {1440, 900}, headless = o.headless}, build, app) { return 1 }
	defer host.host_close(&app.main)
	app.main.background = ui.theme_lookup(&app.shared.theme, {}, "background")
	ui.use(&app.main.state)
	app.main.state.icon_font = ui.lucide_icons()
	app.new_people, app.new_seed = 1, int(o.seed) + 1
	ui.view_register(ui.state_views(&app.main.state), NEW_WORLD_VIEW, new_world_view, ui.View_Options{title = "A new world", icon = lucide.EARTH, width_em = 26})
	if o.dialog { ui.view_open(ui.state_views(&app.main.state), NEW_WORLD_VIEW, app) }
	platform.set_dark_title(app.main.win, true)
	app.devtools = devtools.start_from_env(app.main.win, "agora")
	defer devtools.stop(app.devtools)

	if o.frames >= 0 {
		for _ in 0 ..< o.frames {
			devtools.service(app.devtools, &app.main.state, &app.shared.r)
			host.host_frame(&app.main)
		}
		fmt.printfln("agora: %d frames, %d people, step %d", o.frames, app.snap.agents, app.snap.step)
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

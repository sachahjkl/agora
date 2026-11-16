package agora

// The map: the ground of the snapshot, a layer laid over it, the settlements, the names, a legend and an overview.
// Everything is drawn inside the box's rectangle and clipped to it. A cell is a square on the screen, whatever the box's
// shape: the world is never stretched.

import "core:fmt"
import "core:math"
import "core:slice"
import engine "engine"
import "gt:draw"
import "gt:font"
import "gt:ui"

Layer :: enum {
	Land,
	People,
	Hunger,
	Wealth,
}

LAYER_LABELS := [4]string{"Land", "People", "Hunger", "Wealth"}

ZOOM_MAX :: 24.0

// The side of a cell, in pixels, from which each thing is drawn.
SMOOTH_FROM  :: 9.0  // the ground is blended between cells, not drawn in blocks
HOUSES_FROM  :: 16.0 // a populated cell shows its houses
PEOPLE_FROM  :: 72.0 // a populated cell is a town: its streets, its households' houses, and the chosen cell's people
// The lots along a side of a cell, far (a village) and close (a town, an odd number: the middle one is a street).
VILLAGE_SIDE :: 4
TOWN_SIDE    :: 7
// The people of one house of a town, and the houses a village gains for each mean density it holds past the first.
HOUSEHOLD      :: 4
VILLAGE_HOUSES :: 3.0
// The density, in means of the world, from which a cell is a settled place and not country.
SETTLED :: 1.6
// Cells past the world's edge over which the ground fades into the deep sea.
EDGE_FADE :: 9.0
// The hunger a cell of the Hunger layer is fully red at.
HUNGER_FULL :: 60.0

MAP_SEA   :: 0x0B1A2EFF
MAP_INK   :: 0x0B0D1CFF
MAP_PAPER :: 0xFFF3D6FF
MAP_GOLD  :: 0xF5B94AFF
MAP_CORAL :: 0xF0715FFF
MAP_TEAL  :: 0x4FD1C5FF

Map_Draw :: struct {
	snap:          ^Snapshot,
	layer:         Layer,
	zoom:          f32,
	cx, cy:        f32, // the centre of the view, in cells
	font:          font.Font_Id,
	font_size:     f32,
	selected_cell: int,
	hover_cell:    int,
	selected_person: int,
	probe:         []engine.Probe,
	probe_n:       int,
}

// The part of the world a view shows. `x0, y0` is the cell at the box's top left corner; it is negative when the whole
// world is narrower than the box, and the world is then centred.
Map_View :: struct {
	x0, y0: f32,
	vw, vh: f32, // cells across and down the box
	cell:   f32, // the side of a cell, in pixels
	rect:   draw.Rect,
}

map_view :: proc(s: ^Snapshot, zoom, cx, cy: f32, r: draw.Rect) -> Map_View {
	rw, rh := max(r.max.x - r.min.x, 1), max(r.max.y - r.min.y, 1)
	w, h := f32(max(s.width, 1)), f32(max(s.height, 1))
	v := Map_View{rect = r}
	// (zoom 1: the whole world fits in the box)
	v.cell = clamp(zoom, 1, ZOOM_MAX) * min(rw / w, rh / h)
	v.vw, v.vh = rw / v.cell, rh / v.cell
	v.x0 = v.vw >= w ? (w - v.vw) * 0.5 : clamp(cx - v.vw * 0.5, 0, w - v.vw)
	v.y0 = v.vh >= h ? (h - v.vh) * 0.5 : clamp(cy - v.vh * 0.5, 0, h - v.vh)
	return v
}

// The centre a view really has, once it is kept inside the world: what a drag or a zoom starts from.
map_centre :: proc(v: Map_View) -> (cx, cy: f32) { return v.x0 + v.vw * 0.5, v.y0 + v.vh * 0.5 }

// The cell under a point of the map (-1 outside the world).
cell_at :: proc(v: Map_View, s: ^Snapshot, p: draw.Vec2) -> int {
	if p.x < v.rect.min.x || p.y < v.rect.min.y || p.x >= v.rect.max.x || p.y >= v.rect.max.y { return -1 }
	x := int(math.floor(v.x0 + (p.x - v.rect.min.x) / v.cell))
	y := int(math.floor(v.y0 + (p.y - v.rect.min.y) / v.cell))
	if x < 0 || y < 0 || x >= s.width || y >= s.height { return -1 }
	return y * s.width + x
}

// Where a cell's top left corner is on the screen.
@(private = "file")
cell_pos :: proc(v: Map_View, x, y: f32) -> draw.Vec2 {
	return {v.rect.min.x + (x - v.x0) * v.cell, v.rect.min.y + (y - v.y0) * v.cell}
}

@(private = "file")
outline :: proc(dc: ^draw.Context, r: draw.Rect, width: f32, colour: draw.Color, radius: f32 = 0) {
	draw.rect(dc, r, colour, radius, width)
}

// A text with a dark edge around it, so that it reads over any ground. `pos` is its left and its baseline.
@(private = "file")
map_text :: proc(dc: ^draw.Context, d: ^Map_Draw, size: f32, pos: draw.Vec2, colour: draw.Color, text: string) {
	ink := draw.hex(MAP_INK)
	ink.a = 0.85
	for o in ([4]draw.Vec2{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) { draw.text(dc, d.font, size, pos + o, ink, text) }
	draw.text(dc, d.font, size, pos, colour, text)
}

map_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Map_Draw)(user)
	s := d.snap
	if s.width == 0 || len(s.people) == 0 { return }
	// (a pixel inside the box: the frame around the map keeps its edge)
	r := draw.Rect{b.rect.min + {1, 1}, b.rect.max - {1, 1}}
	v := map_view(s, d.zoom, d.cx, d.cy, r)
	radius := math.round(d.font_size * 0.4)
	draw.push_clip_rounded(dc, r, {radius, radius, radius, radius})
	defer draw.pop_clip(dc)
	draw.rect(dc, r, draw.hex(MAP_SEA))
	map_ground(dc, d, v)
	if v.cell >= HOUSES_FROM { map_houses(dc, d, v) }
	map_marks(dc, d, v)
	map_names(dc, d, v)
	map_legend(dc, d, r)
	if v.vw < f32(s.width) - 0.5 || v.vh < f32(s.height) - 0.5 { map_overview(dc, d, v, r) }
}

// The colour of a cell: its ground, and the layer's tint where people live.
@(private = "file")
cell_colour :: proc(d: ^Map_Draw, x, y: int) -> draw.Color {
	s := d.snap
	cx, cy := clamp(x, 0, s.width - 1), clamp(y, 0, s.height - 1)
	c := cy * s.width + cx
	colour := ground_colour(s, cx, cy, c)
	if d.layer != .Land && s.people[c] > 0 {
		colour = draw.mix(colour, layer_colour(d.layer, layer_level(s, c, d.layer)), 0.86)
	}
	// past the world's edge, its last cell fades into the deep sea: the world has no visible border
	if out := max(-x, x - (s.width - 1), -y, y - (s.height - 1)); out > 0 {
		colour = draw.mix(colour, draw.hex(MAP_SEA), clamp(f32(out) / EDGE_FADE, 0, 1))
	}
	return colour
}

// How far a cell is along its layer's scale, from 0 to 1.
layer_level :: proc(s: ^Snapshot, c: int, layer: Layer) -> f32 {
	people := f64(s.people[c])
	if people <= 0 { return 0 }
	level: f64
	switch layer {
	case .Land:
	case .People:
		level = people / max(2 * s.mean_density, 1)
	case .Hunger:
		level = f64(s.hunger[c]) / people / HUNGER_FULL
	case .Wealth:
		level = f64(s.money[c]) / people / max(2 * s.mean_wealth, 1)
	}
	return f32(clamp(level, 0, 1))
}

// The ground. Far, one rectangle a cell. Close, each cell is cut in smaller squares whose colours are blended with the
// neighbours': a coast is a soft line, not a staircase.
@(private = "file")
map_ground :: proc(dc: ^draw.Context, d: ^Map_Draw, v: Map_View) {
	// (the cells of the box, those past the world's edge too: cell_colour fades them)
	x_lo, y_lo := int(math.floor(v.x0)), int(math.floor(v.y0))
	x_hi, y_hi := int(math.ceil(v.x0 + v.vw)), int(math.ceil(v.y0 + v.vh))
	if x_hi <= x_lo || y_hi <= y_lo { return }
	// the colours of the cells shown and of one more around them, for the blend
	gw, gh := x_hi - x_lo + 2, y_hi - y_lo + 2
	colours := make([]draw.Color, gw * gh, context.temp_allocator)
	for gy in 0 ..< gh {
		for gx in 0 ..< gw { colours[gy * gw + gx] = cell_colour(d, x_lo + gx - 1, y_lo + gy - 1) }
	}
	sub := v.cell >= SMOOTH_FROM ? clamp(int(v.cell / 7), 2, 5) : 1
	step := v.cell / f32(sub)
	for y in y_lo ..< y_hi {
		for x in x_lo ..< x_hi {
			gx, gy := x - x_lo + 1, y - y_lo + 1
			at := cell_pos(v, f32(x), f32(y))
			if sub == 1 {
				draw.rect(dc, {at, at + {v.cell + 0.5, v.cell + 0.5}}, colours[gy * gw + gx])
				continue
			}
			for j in 0 ..< sub {
				for i in 0 ..< sub {
					// where the small square's middle is between the middles of the four nearest cells
					fx := (f32(i) + 0.5) / f32(sub) - 0.5
					fy := (f32(j) + 0.5) / f32(sub) - 0.5
					ax, ay := fx < 0 ? gx - 1 : gx, fy < 0 ? gy - 1 : gy
					tx, ty := fx < 0 ? fx + 1 : fx, fy < 0 ? fy + 1 : fy
					top := draw.mix(colours[ay * gw + ax], colours[ay * gw + ax + 1], tx)
					bottom := draw.mix(colours[(ay + 1) * gw + ax], colours[(ay + 1) * gw + ax + 1], tx)
					p := at + {f32(i) * step, f32(j) * step}
					draw.rect(dc, {p, p + {step + 0.5, step + 0.5}}, draw.mix(top, bottom, ty))
				}
			}
		}
	}
}

// True when a cell is a settled place: more people than SETTLED times the world's mean. The rest of the lived land is
// country.
settled :: proc(s: ^Snapshot, x, y: int) -> bool {
	if x < 0 || y < 0 || x >= s.width || y >= s.height { return false }
	return f64(s.people[y * s.width + x]) >= SETTLED * max(s.mean_density, 1)
}

// The houses of the populated cells: more people, more houses, always at the same places of the cell.
@(private = "file")
map_houses :: proc(dc: ^draw.Context, d: ^Map_Draw, v: Map_View) {
	s := d.snap
	x_lo, y_lo := max(0, int(math.floor(v.x0))), max(0, int(math.floor(v.y0)))
	x_hi, y_hi := min(s.width, int(math.ceil(v.x0 + v.vw))), min(s.height, int(math.ceil(v.y0 + v.vh)))
	if x_hi <= x_lo || y_hi <= y_lo { return }
	town := v.cell >= PEOPLE_FROM
	side := town ? TOWN_SIDE : VILLAGE_SIDE
	lot := v.cell / f32(side)
	// the lots of a cell, the nearest its middle first: a place grows from its middle outwards. A town keeps its
	// middle row and its middle column for its two streets.
	Lot :: struct {
		x, y: int,
		far:  f32,
	}
	lots: [TOWN_SIDE * TOWN_SIDE]Lot
	lots_n := 0
	for ly in 0 ..< side {
		for lx in 0 ..< side {
			if town && (lx == side / 2 || ly == side / 2) { continue }
			dx, dy := f32(lx) - f32(side - 1) * 0.5, f32(ly) - f32(side - 1) * 0.5
			lots[lots_n] = {lx, ly, dx * dx + dy * dy}
			lots_n += 1
		}
	}
	slice.sort_by(lots[:lots_n], proc(a, b: Lot) -> bool { return a.far < b.far })
	if town {
		// the streets first, under the houses: an arm towards each neighbour that has people
		street := draw.hex(0xCDBE96FF)
		half := lot * 0.22
		for y in y_lo ..< y_hi {
			for x in x_lo ..< x_hi {
				if !settled(s, x, y) { continue }
				mid := cell_pos(v, f32(x) + 0.5, f32(y) + 0.5)
				lived :: settled
				west, east := lived(s, x - 1, y) ? v.cell * 0.5 : lot, lived(s, x + 1, y) ? v.cell * 0.5 : lot
				north, south := lived(s, x, y - 1) ? v.cell * 0.5 : lot, lived(s, x, y + 1) ? v.cell * 0.5 : lot
				draw.rect(dc, {mid - {west, half}, mid + {east, half}}, street)
				draw.rect(dc, {mid - {half, north}, mid + {half, south}}, street)
			}
		}
	}
	walls := [3]draw.Color{draw.hex(0xEFE3C8FF), draw.hex(0xE3D2B0FF), draw.hex(0xF4EBD8FF)}
	roofs := [3]draw.Color{draw.hex(0xA8503AFF), draw.hex(0x8C4632FF), draw.hex(0xB9643FFF)}
	shade, door := draw.hex(0x00000055), draw.hex(0x5A3A28FF)
	size := max(2, math.round(lot * (town ? 0.56 : 0.6)))
	for y in y_lo ..< y_hi {
		for x in x_lo ..< x_hi {
			c := y * s.width + x
			people := int(s.people[c])
			if people == 0 { continue }
			// a settled cell: a house for each household, seen close; seen from afar, as many as it is denser than the
			// world. The country around: a farm here and there.
			place := settled(s, x, y)
			houses: int
			if !place {
				houses = int(engine.splitmix64(u64(c) * 0xC2B2AE3D) % 3) / 2 + (town ? 1 : 0)
			} else if town {
				houses = people / HOUSEHOLD + 1
			} else {
				houses = int(math.round((f64(people) / max(s.mean_density, 1) - 1) * VILLAGE_HOUSES)) + 2
			}
			houses = clamp(houses, 0, lots_n)
			at := cell_pos(v, f32(x), f32(y))
			for i in 0 ..< houses {
				// (a hash of the cell and the lot: a house keeps its look and its place from frame to frame)
				h := engine.splitmix64(u64(c) * 0x9E3779B1 + u64(i) * 0x85EBCA77)
				shift := draw.Vec2{f32(h & 0xFF) / 255 - 0.5, f32((h >> 8) & 0xFF) / 255 - 0.5} * (lot - size) * 0.7
				// (a place fills its lots from its middle; a farm stands on any lot)
				l := place ? lots[i] : lots[int((h >> 28) % u64(lots_n))]
				p := at + {(f32(l.x) + 0.5) * lot, (f32(l.y) + 0.5) * lot} + shift - {size, size} * 0.5
				p = {math.round(p.x), math.round(p.y)}
				if !town {
					draw.rect(dc, {p + {1, 1}, p + {size + 1, size + 1}}, shade)
					draw.rect(dc, {p, p + {size, size}}, walls[(h >> 16) % 3])
					draw.rect(dc, {p, p + {size, math.ceil(size * 0.5)}}, roofs[(h >> 20) % 3])
					continue
				}
				eave := math.round(size * 0.08)
				draw.rect(dc, {p + {2, size * 0.45 + 2}, p + {size + 2, size + 2}}, shade)
				draw.rect(dc, {p + {0, size * 0.4}, p + {size, size}}, walls[(h >> 16) % 3])
				draw.rect(dc, {p - {eave, 0}, p + {size + eave, size * 0.5}}, roofs[(h >> 20) % 3], 2)
				draw.rect(dc, {p + {size * 0.4, size * 0.68}, p + {size * 0.6, size}}, door)
			}
		}
	}
}

// The cell under the pointer, the chosen cell and its people, and the biggest places' dots.
@(private = "file")
map_marks :: proc(dc: ^draw.Context, d: ^Map_Draw, v: Map_View) {
	s := d.snap
	paper := draw.hex(MAP_PAPER)
	if v.cell < HOUSES_FROM {
		for i in 0 ..< s.cities_n {
			city := s.cities[i]
			p := cell_pos(v, f32(city.x) + 0.5, f32(city.y) + 0.5)
			radius := clamp(v.cell * 0.45, 2.5, 5)
			draw.rect(dc, {p - {radius + 1, radius + 1}, p + {radius + 1, radius + 1}}, draw.hex(MAP_INK), radius + 1)
			draw.rect(dc, {p - {radius, radius}, p + {radius, radius}}, paper, radius)
		}
	}
	if d.hover_cell >= 0 && d.hover_cell != d.selected_cell && v.cell >= 5 {
		at := cell_pos(v, f32(d.hover_cell % s.width), f32(d.hover_cell / s.width))
		faint := paper
		faint.a = 0.55
		outline(dc, {at, at + {v.cell, v.cell}}, 1, faint)
	}
	if d.selected_cell < 0 || d.selected_cell >= s.width * s.height { return }
	at := cell_pos(v, f32(d.selected_cell % s.width), f32(d.selected_cell / s.width))
	grow := max(0, (7 - v.cell) * 0.5) // (a cell too small to see keeps a ring one can see)
	ring := draw.Rect{at - {grow, grow}, at + {v.cell + grow, v.cell + grow}}
	outline(dc, {ring.min - {1, 1}, ring.max + {1, 1}}, 4, draw.hex(MAP_INK), 3)
	outline(dc, ring, 2, draw.hex(MAP_GOLD), 2)
	if v.cell < PEOPLE_FROM || d.probe_n == 0 { return }
	// its people, on its two streets: one disc each, redder as it is hungrier; the chosen person wears a gold ring
	dot := clamp(v.cell / 30, 3, 6)
	road := v.cell / TOWN_SIDE
	for i in 0 ..< d.probe_n {
		h := engine.splitmix64(u64(d.probe[i].id) * 0x9E3779B1 + 7)
		along := v.cell * (0.05 + 0.9 * f32(h & 0xFFFF) / 65535)
		across := v.cell * 0.5 + road * 0.3 * (f32((h >> 16) & 0xFFFF) / 65535 - 0.5)
		p := at + ((h >> 40) & 1 == 0 ? draw.Vec2{along, across} : draw.Vec2{across, along})
		colour := draw.mix(paper, draw.hex(MAP_CORAL), f32(d.probe[i].hunger) / 100)
		if int(d.probe[i].id) == d.selected_person {
			draw.rect(dc, {p - {dot + 4, dot + 4}, p + {dot + 4, dot + 4}}, draw.hex(MAP_GOLD), dot + 4)
		}
		draw.rect(dc, {p - {dot + 1, dot + 1}, p + {dot + 1, dot + 1}}, draw.hex(MAP_INK), dot + 1)
		draw.rect(dc, {p - {dot, dot}, p + {dot, dot}}, colour, dot)
	}
}

// The names of the biggest places and of the chosen one. A name that would cover another is not drawn.
@(private = "file")
map_names :: proc(dc: ^draw.Context, d: ^Map_Draw, v: Map_View) {
	s := d.snap
	if d.font == 0 { return }
	size := math.round(d.font_size * 0.95)
	taken: [CITY_SLOTS + 1]draw.Rect
	taken_n := 0
	name_at :: proc(dc: ^draw.Context, d: ^Map_Draw, v: Map_View, x, y: int, size: f32, taken: []draw.Rect, taken_n: ^int, colour: draw.Color) {
		name := city_name(x, y)
		p := cell_pos(v, f32(x) + 0.5, f32(y) + 0.5)
		lift := v.cell >= HOUSES_FROM ? v.cell * 0.5 + 4 : 9
		width := font.text_width(dc.fonts, d.font, size, name)
		box := draw.Rect{{p.x - width * 0.5 - 4, p.y - lift - size - 2}, {p.x + width * 0.5 + 4, p.y - lift + 4}}
		if box.max.x < v.rect.min.x || box.min.x > v.rect.max.x || box.max.y < v.rect.min.y || box.min.y > v.rect.max.y { return }
		for t in taken[:taken_n^] {
			if box.min.x < t.max.x && box.max.x > t.min.x && box.min.y < t.max.y && box.max.y > t.min.y { return }
		}
		taken[taken_n^] = box
		taken_n^ += 1
		map_text(dc, d, size, {box.min.x + 4, p.y - lift}, colour, name)
	}
	if d.selected_cell >= 0 && d.selected_cell < s.width * s.height {
		name_at(dc, d, v, d.selected_cell % s.width, d.selected_cell / s.width, size, taken[:], &taken_n, draw.hex(MAP_GOLD))
	}
	for i in 0 ..< s.cities_n {
		name_at(dc, d, v, s.cities[i].x, s.cities[i].y, size, taken[:], &taken_n, draw.hex(MAP_PAPER))
	}
}

BIOMES_SHOWN :: [7]engine.Biome{.Ocean, .Ice, .Tundra, .Desert, .Grass, .Forest, .Mountain}

// The legend, at the map's lower left: the grounds and their colours, or the layer's scale and its two ends.
@(private = "file")
map_legend :: proc(dc: ^draw.Context, d: ^Map_Draw, r: draw.Rect) {
	s := d.snap
	if d.font == 0 { return }
	size := math.round(d.font_size * 0.85)
	pad, gap, swatch := math.round(size * 0.75), math.round(size * 0.9), math.round(size * 0.8)
	height := size + pad * 2
	text := draw.hex(0xECEFF5FF)
	back := draw.hex(MAP_INK)
	back.a = 0.86
	edge := draw.Color{1, 1, 1, 0.14}
	origin := draw.Vec2{r.min.x + pad, r.max.y - pad - height}
	baseline := origin.y + pad + size * 0.82
	if d.layer == .Land {
		biomes := BIOMES_SHOWN
		width := pad
		for b in biomes { width += swatch + 5 + font.text_width(dc.fonts, d.font, size, biome_name(u8(b))) + gap }
		width += pad - gap
		box := draw.Rect{origin, origin + {width, height}}
		draw.rect(dc, box, back, 6)
		outline(dc, box, 1, edge, 6)
		x := origin.x + pad
		for b in biomes {
			y := origin.y + (height - swatch) * 0.5
			draw.rect(dc, {{x, y}, {x + swatch, y + swatch}}, biome_colour(u8(b)), 2)
			x += swatch + 5
			x += draw.text(dc, d.font, size, {x, baseline}, text, biome_name(u8(b))) + gap
		}
		return
	}
	name := LAYER_LABELS[int(d.layer)]
	low, high: string
	switch d.layer {
	case .Land:
	case .People:
		low, high = "0", fmt.tprintf("%.0f a cell", 2 * s.mean_density)
	case .Hunger:
		low, high = "fed", "starving"
	case .Wealth:
		low, high = "0", fmt.tprintf("%s each", compact(2 * s.mean_wealth))
	}
	bar_w := size * 9
	name_w, low_w, high_w := font.text_width(dc.fonts, d.font, size, name), font.text_width(dc.fonts, d.font, size, low), font.text_width(dc.fonts, d.font, size, high)
	width := pad + name_w + gap + low_w + 6 + bar_w + 6 + high_w + pad
	box := draw.Rect{origin, origin + {width, height}}
	draw.rect(dc, box, back, 6)
	outline(dc, box, 1, edge, 6)
	x := origin.x + pad
	draw.text(dc, d.font, size, {x, baseline}, text, name)
	x += name_w + gap
	weak := text
	weak.a = 0.7
	draw.text(dc, d.font, size, {x, baseline}, weak, low)
	x += low_w + 6
	STEPS :: 32
	for i in 0 ..< STEPS {
		a, b := x + bar_w * f32(i) / STEPS, x + bar_w * f32(i + 1) / STEPS
		draw.rect(dc, {{a, origin.y + pad + 1}, {b + 0.5, origin.y + height - pad - 1}}, layer_colour(d.layer, f32(i) / (STEPS - 1)))
	}
	x += bar_w + 6
	draw.text(dc, d.font, size, {x, baseline}, weak, high)
}

// The overview, at the map's upper right, once the view is closer than the whole world: the world, small, and the part
// of it the view shows.
@(private = "file")
map_overview :: proc(dc: ^draw.Context, d: ^Map_Draw, v: Map_View, r: draw.Rect) {
	s := d.snap
	STEP :: 2 // cells a square of the overview stands for
	pad := math.round(d.font_size * 0.7)
	px := math.round(clamp((r.max.x - r.min.x) * 0.2 / f32(s.width / STEP), 1, 3))
	w, h := f32(s.width / STEP) * px, f32(s.height / STEP) * px
	origin := draw.Vec2{r.max.x - pad - w, r.min.y + pad}
	frame := draw.Rect{origin - {3, 3}, origin + {w + 3, h + 3}}
	draw.rect(dc, frame, draw.hex(MAP_INK), 5)
	for y in 0 ..< s.height / STEP {
		for x in 0 ..< s.width / STEP {
			c := (y * STEP) * s.width + x * STEP
			p := origin + {f32(x) * px, f32(y) * px}
			draw.rect(dc, {p, p + {px, px}}, ground_colour(s, x * STEP, y * STEP, c))
		}
	}
	scale := px / STEP
	a := origin + {max(v.x0, 0) * scale, max(v.y0, 0) * scale}
	b := origin + {min(v.x0 + v.vw, f32(s.width)) * scale, min(v.y0 + v.vh, f32(s.height)) * scale}
	outline(dc, {a - {1, 1}, b + {1, 1}}, 3, draw.hex(MAP_INK))
	outline(dc, {a, b}, 1.5, draw.hex(MAP_GOLD))
	outline(dc, frame, 1, {1, 1, 1, 0.18}, 5)
}

// A place's name, made from where it is: the same cell always has the same name.
city_name :: proc(x, y: int) -> string {
	first := [12]string{"Ash", "Bran", "Cor", "Dun", "El", "Fen", "Gal", "Hal", "Mor", "Nor", "Os", "Wyn"}
	second := [10]string{"mere", "ford", "wick", "ton", "holm", "dale", "bay", "reth", "stead", "haven"}
	h := engine.splitmix64(u64(x) * 0x9E3779B1 + u64(y) * 0x85EBCA77)
	return fmt.tprintf("%s%s", first[h % len(first)], second[(h >> 20) % len(second)])
}

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

// The ground of one cell: its biome's colour, its sea's depth, and the slope's light.
ground_colour :: proc(s: ^Snapshot, x, y, c: int) -> draw.Color {
	biome := engine.Biome(s.biome[c])
	height := f32(s.elevation[c]) / 65535
	colour := biome_colour(s.biome[c])
	#partial switch biome {
	case .Ocean:
		return draw.mix(draw.hex(MAP_SEA), draw.hex(0x1F506EFF), clamp((height - 0.25) / 0.25, 0, 1))
	case .Mountain:
		if height > 0.94 { colour = draw.hex(0xE4EBF0FF) }
	}
	// the light: a slope that climbs to the north-west is bright, one that falls that way is dark
	dx, dy: f32
	if x > 0 && x + 1 < s.width { dx = f32(s.elevation[c + 1]) - f32(s.elevation[c - 1]) }
	if y > 0 && y + 1 < s.height { dy = f32(s.elevation[c + s.width]) - f32(s.elevation[c - s.width]) }
	shade := clamp(1.05 - (dx + dy) / 9000, 0.62, 1.45)
	return {clamp(colour.r * shade, 0, 1), clamp(colour.g * shade, 0, 1), clamp(colour.b * shade, 0, 1), colour.a}
}

// The layer's colour at t in [0, 1]: dark indigo to the layer's own bright hue.
layer_colour :: proc(layer: Layer, t: f32) -> draw.Color {
	base := draw.hex(0x10142CFF)
	switch layer {
	case .Land:
	case .People:
		return draw.mix(base, draw.hex(MAP_GOLD), clamp(t, 0, 1))
	case .Hunger:
		return draw.mix(base, draw.hex(MAP_CORAL), clamp(t, 0, 1))
	case .Wealth:
		return draw.mix(base, draw.hex(MAP_TEAL), clamp(t, 0, 1))
	}
	return base
}

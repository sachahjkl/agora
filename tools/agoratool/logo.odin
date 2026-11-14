package agoratool

// logo: agora's mark, drawn by the toolkit's paint package (the same bytes on every system). A world seen from above: a
// dark disc, and in it three groups of people, gold, teal and coral, each tied together by its own links, with fewer and
// fainter links between the groups. Sizes up to 32 px draw one dot per group (detail_for), so the mark still reads at
// 16 px. The files are the toolkit's (toolbox.write_logo, docs/toolbox.md, "A program's logo"); the sharing card is
// `agoratool card`, drawn here rather than by gt:site's draw_card, which needs a browser.

import "core:fmt"
import "core:os"
import paint "gt:paint"
import toolbox "gt:toolbox"

LOGO_DIR    :: "assets"
LOGO_MASTER :: 1024
LOGO_SIZES  := [?]int{16, 24, 32, 48, 64, 128, 256, 512}
// The site's copy of the logo, and its size.
SITE_LOGOS := [?]toolbox.Logo_File{{path = "site/img/logo.png", size = 256}}
// The drawing's own units: a square of LOGO_UNITS, scaled to the canvas.
LOGO_UNITS  :: 512.0
// Small sizes are drawn from a master this many times larger, in one step of the cubic filter at most this factor.
LOGO_SHRINK_STEP :: 4

// The world: its centre and radius, in units.
WORLD_X :: 256.0
WORLD_Y :: 256.0
WORLD_R :: 240.0

// The colours.
WORLD_CENTRE :: 0x2A2F5C
WORLD_EDGE   :: 0x0E1022
WORLD_RIM    :: 0x464E8C
GOLD         :: 0xF5B94A
TEAL         :: 0x4FD1C5
CORAL        :: 0xF0715F
BRIDGE       :: 0xFFFFFF

// A group: its colour and the places of its people.
Group :: struct {
	colour: u32,
	people: [4][2]f32,
}

GROUPS :: [3]Group{
	{GOLD, {{256, 104}, {208, 160}, {304, 160}, {256, 206}}},
	{TEAL, {{146, 296}, {108, 356}, {176, 382}, {200, 322}}},
	{CORAL, {{366, 296}, {404, 356}, {336, 382}, {312, 322}}},
}

// The links between groups: a person of one to a person of another (group, person).
BRIDGES :: [3][2][2]int{
	{{0, 3}, {1, 3}},
	{{0, 3}, {2, 3}},
	{{1, 2}, {2, 2}},
}

// One dot per group, for the small sizes.
SMALL_PEOPLE :: [3][2]f32{{256, 150}, {150, 344}, {362, 344}}

// 1: every person and link (48 px and up); 0: one dot per group (16 to 32).
detail_for :: proc(size: int) -> int { return size <= 32 ? 0 : 1 }

logo :: proc() -> toolbox.Logo {
	return {
		render = logo_render,
		dir = LOGO_DIR,
		master = LOGO_MASTER,
		sizes = LOGO_SIZES[:],
		project_image = true,
		files = SITE_LOGOS[:],
	}
}

@(private = "file")
circle :: proc(p: ^paint.Path, cx, cy, r: f32) { paint.ellipse(p, cx - r, cy - r, r * 2, r * 2) }

@(private = "file")
segment :: proc(c: ^paint.Canvas, a, b: [2]f32, width: f32, colour: u32, alpha: int) {
	p: paint.Path
	defer paint.path_destroy(&p)
	paint.move_to(&p, a.x, a.y)
	paint.line_to(&p, b.x, b.y)
	paint.stroke(c, p, {width = width, cap = .Round}, paint.solid(paint.hex(colour, alpha)))
}

@(private = "file")
dot :: proc(c: ^paint.Canvas, at: [2]f32, r: f32, colour: u32) {
	p: paint.Path
	defer paint.path_destroy(&p)
	circle(&p, at.x, at.y, r)
	// (lit from the top left: the colour mixed with white there, the colour itself at the far edge)
	paint.fill(c, p, paint.radial({at.x - r * 0.35, at.y - r * 0.4}, r * 1.4, paint.hex(lighten(colour, 0.45)), paint.hex(colour)))
}

// `colour` moved towards white by `amount` (0: itself, 1: white).
@(private = "file")
lighten :: proc(colour: u32, amount: f32) -> u32 {
	out: u32
	for shift in ([3]u32{16, 8, 0}) {
		v := f32((colour >> shift) & 0xFF)
		out |= u32(v + (255 - v) * amount) << shift
	}
	return out
}

logo_draw :: proc(size: int, detail: int) -> paint.Canvas {
	c := paint.canvas_make(size, size)
	logo_paint(&c, 0, 0, f32(size), detail)
	return c
}

// The mark on `c`, in the square of side `size` whose top left corner is (x, y).
logo_paint :: proc(canvas: ^paint.Canvas, x, y, size: f32, detail: int) {
	c := canvas
	k := size / LOGO_UNITS
	c.transform = paint.scale(paint.translate(paint.IDENTITY, x, y), k, k)
	defer c.transform = paint.IDENTITY

	// the world: dark at its edge, lighter at its centre, with a rim
	world: paint.Path
	defer paint.path_destroy(&world)
	circle(&world, WORLD_X, WORLD_Y, WORLD_R)
	paint.fill(c, world, paint.radial({WORLD_X, WORLD_Y - 40}, WORLD_R * 1.1, paint.hex(WORLD_CENTRE), paint.hex(WORLD_EDGE)))
	rim: paint.Path
	defer paint.path_destroy(&rim)
	circle(&rim, WORLD_X, WORLD_Y, WORLD_R - 6)
	paint.stroke(c, rim, {width = detail == 0 ? 20 : 10}, paint.solid(paint.hex(WORLD_RIM)))

	groups := GROUPS
	if detail == 0 {
		small := SMALL_PEOPLE
		for i in 0 ..< 3 { segment(c, small[i], small[(i + 1) % 3], 30, BRIDGE, 150) }
		for g, i in groups { dot(c, small[i], 66, g.colour) }
		return
	}

	// the links between groups first, under everything: thin and faint
	bridges := BRIDGES
	for b in bridges {
		segment(c, groups[b[0][0]].people[b[0][1]], groups[b[1][0]].people[b[1][1]], 7, BRIDGE, 70)
	}
	// each group's own links: every person to every other, in the group's colour
	for g in groups {
		for i in 0 ..< len(g.people) {
			for j in i + 1 ..< len(g.people) { segment(c, g.people[i], g.people[j], 9, g.colour, 150) }
		}
	}
	for g in groups {
		for q in g.people { dot(c, q, 24, g.colour) }
	}
}

// The picture at `size`: drawn large, then shrunk in steps the cubic filter keeps clean.
logo_render :: proc(size: int, user: rawptr) -> paint.Canvas {
	n := size
	for n < LOGO_MASTER { n *= LOGO_SHRINK_STEP }
	c := logo_draw(n, detail_for(size))
	for n > size {
		next := max(n / LOGO_SHRINK_STEP, size)
		small := paint.resize(c, next, next)
		paint.canvas_destroy(&c)
		c, n = small, next
	}
	return c
}

// `agoratool card`: the sharing card (SITE_META.card), the mark on the site's night, with the groups' colours spread
// faintly behind it. Drawn here: no browser, the same bytes on every system.
CARD_PATH       :: "site/img/card.png"
CARD_W          :: 1200
CARD_H          :: 630
CARD_BACKGROUND :: 0x0B0D1C
CARD_MARK       :: 440

run_card :: proc(args: []string) -> int {
	if len(args) > 0 { fmt.eprintln("card takes no argument"); return toolbox.EXIT_USAGE }
	c := paint.canvas_make(CARD_W, CARD_H)
	defer paint.canvas_destroy(&c)
	whole: paint.Path
	defer paint.path_destroy(&whole)
	paint.rect(&whole, 0, 0, CARD_W, CARD_H)
	paint.fill(&c, whole, paint.solid(paint.hex(CARD_BACKGROUND)))
	// a glow of each group's colour, far apart: the world they live in
	glows := [3]struct {
		x, y: f32,
		colour: u32,
	}{{240, 140, GOLD}, {170, 560, TEAL}, {1040, 470, CORAL}}
	for g in glows { paint.fill(&c, whole, paint.radial({g.x, g.y}, 520, paint.hex(g.colour, 60), paint.hex(g.colour, 0))) }
	logo_paint(&c, (CARD_W - CARD_MARK) / 2, (CARD_H - CARD_MARK) / 2, CARD_MARK, 1)
	_ = os.make_directory_all("site/img")
	if !paint.write_png(c, CARD_PATH) { fmt.eprintfln("agoratool: %s cannot be written", CARD_PATH); return toolbox.EXIT_FAILED }
	fmt.printfln("wrote %s", CARD_PATH)
	return toolbox.EXIT_DONE
}

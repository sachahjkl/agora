package agora

import "core:testing"
import "gt:draw"

// The whole world fits in the box at zoom 1 and is centred there; a cell is a square.
@(test)
test_map_view_fits :: proc(t: ^testing.T) {
	s := Snapshot{width = 160, height = 96}
	r := draw.Rect{{10, 20}, {1010, 770}}
	v := map_view(&s, 1, 80, 48, r)
	testing.expect_value(t, v.cell, f32(6.25))
	testing.expect(t, v.x0 == 0, "the world is as wide as the box")
	testing.expect(t, v.y0 < 0, "the world is shorter than the box: it is centred")
	testing.expect_value(t, cell_at(v, &s, {10, 20}), -1)
	testing.expect_value(t, cell_at(v, &s, {10 + 6.25 * 3.5, 20 - v.y0 * 6.25 + 6.25 * 2.5}), 2 * 160 + 3)
}

// A view never leaves the world: its centre is brought back inside.
@(test)
test_map_view_stays_inside :: proc(t: ^testing.T) {
	s := Snapshot{width = 160, height = 96}
	r := draw.Rect{{0, 0}, {1000, 750}}
	v := map_view(&s, 8, -500, 9000, r)
	testing.expect_value(t, v.x0, f32(0))
	testing.expect_value(t, v.y0, 96 - v.vh)
	cx, cy := map_centre(v)
	again := map_view(&s, 8, cx, cy, r)
	testing.expect_value(t, again.x0, v.x0)
	testing.expect_value(t, again.y0, v.y0)
}

// A place is the most populated cell of its reach; of two equal cells, one only.
@(test)
test_is_peak :: proc(t: ^testing.T) {
	people := make([]u32, 10 * 10, context.temp_allocator)
	people[5 * 10 + 5] = 40
	people[5 * 10 + 6] = 30
	people[1 * 10 + 1] = 7
	people[1 * 10 + 2] = 7
	testing.expect(t, is_peak(people, 10, 10, 5 * 10 + 5), "the most populated cell is a place")
	testing.expect(t, !is_peak(people, 10, 10, 5 * 10 + 6), "its neighbour is a part of it")
	testing.expect(t, is_peak(people, 10, 10, 1 * 10 + 1), "of two equal cells, the first is the place")
	testing.expect(t, !is_peak(people, 10, 10, 1 * 10 + 2), "and the second is not")
}

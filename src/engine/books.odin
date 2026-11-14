package engine

// The books of a step. Goods are created by production and destroyed by eating; money only moves between agents. The
// two identities below must hold to the unit, after every step: they are the design's first test. The totals are summed
// by the phases themselves (sort_by_market opens the books, measure closes them), so the books cost no pass of their own.

import "core:fmt"

// Goods: what was there, plus what was produced, less what was eaten. Money: what was there (it only changes hands).
books_balanced :: proc(w: ^World) -> bool {
	b := w.books
	return b.goods_end == b.goods_start + b.produced - b.consumed && b.money_end == b.money_start
}

// Why the books do not balance ("" when they do): for a test's message, and the command line's last line.
books_why :: proc(w: ^World) -> string {
	b := w.books
	if b.goods_end != b.goods_start + b.produced - b.consumed {
		return fmt.tprintf("goods: end %d, start %d + produced %d - consumed %d", b.goods_end, b.goods_start, b.produced, b.consumed)
	}
	if b.money_end != b.money_start {
		return fmt.tprintf("money: end %d, start %d", b.money_end, b.money_start)
	}
	return ""
}

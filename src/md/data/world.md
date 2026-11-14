# The world's data

## Columns

| Column | Type | Meaning |
|---|---|---|
| `cell` | `[]u32` | the agent's cell, from 0 to width × height − 1 |
| `goods` | `[]i64` | what the agent holds, in centi-units (100 = one meal) |
| `money` | `[]i64` | what the agent holds, in the money's smallest unit |
| `hunger` | `[]u8` | 0 (fed) to 100 (starving) |
| `health` | `[]u8` | 0 to 100 |
| `skill` | `[]u8` | 50 to 150: what this person gets out of the land, in percent |

The grid: one `Cell` per cell of `width × height`, with its `productivity` (200 to 1000 per thousand). The land is a river
valley, a sine of the rows; it is the same for every seed, so that two seeds are comparable.

The markets: one per region of `REGION × REGION` (4×4) cells, with a `price` in money per unit, and the buyers and
sellers of its last step. `market_start[m] ..< market_start[m+1]` are its agents in `order`.

## Units

- Goods are **centi-units**: a hundredth of a meal. A division that would lose a fraction is avoided by keeping the
  quantity in centi-units; the books stay exact.
- Money is an integer in its smallest unit. A price is money per **unit** (not per centi-unit); a trade costs
  `qty * price / GOOD`, with `qty` a whole number of centi-units.
- Hunger is a 0–100 level, not a quantity: one unit of food removes `EAT_PER_UNIT` (10) of it.

## The constants

| Constant | Value | Effect |
|---|---|---|
| `PRODUCE_DIVISOR` | 20,000 | productivity × health × skill, divided: about 2.5 units a step on average land |
| `PRICE_BASE` | 50,000 | a market's price: `PRICE_BASE / mean productivity`, money per unit |
| `HUNGER_PER_STEP` | 20 | about two units of food a step |
| `EAT_PER_UNIT` | 10 | hunger removed by one meal |
| `SURPLUS` | 3 units | what an agent keeps before it sells |
| `BUY_BELOW` | 20 | an agent buys when its hunger is above this |
| `STARVING` | 70 | above this hunger, health falls |
| `REGION` | 4 | cells across one market |

## Invariants

1. `goods_end == goods_start + produced - consumed` after every step.
2. `money_end == money_start` after every step: money moves, it is never created.
3. No sensor changes a column, a draw or an aggregate.
4. The same seed and the same options give the same columns after the same number of steps.

## The order

`order` holds every agent's index, sorted by market with a stable counting sort. `market_start` is its prefix sum, and
`cell_cursor` is the working copy that places each agent. The sort is also where the step's books open: its counting loop
adds the totals of goods and money, which is one pass less over the columns.

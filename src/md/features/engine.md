# The engine

The engine is `src/engine`. It knows no window, no file and no thread: `world_make` founds a world, `world_step` advances
it, `world_destroy` frees it. The command line is its first caller; the viewer will be the second.

## A step

```
world_step
  rng_step_seed        splitmix64(seed ~ splitmix64(step)): the root of this step's draws
  sort_by_market       the agents in market order (stable counting sort); opens the books
  produce_and_intend   each person works its land, writes what it wants: sell its surplus, or buy food
  resolve_markets      each market meets its buyers and sellers in order, at its price
  eat_and_modulate     each person eats, its hunger grows, its health follows
  measure              the aggregates and the histogram, the books' totals, then the sensors due
```

The order is a rule, not a taste. Intentions are written before any market clears, so no agent sees a price its own
trade moved. The books open before anything changes and close in the measure pass, so they cost no pass of their own.
Each phase reads the state at t and writes the state at t+1; a phase never reads what it has already written.

## Determinism

- The seed founds the world: each person's cell, stock, money, hunger, health and skill come from
  `splitmix64` of the seed and the agent's number, one stream per field (`Use.Home`, `Use.Goods`...).
- A step's draws come from one root, `splitmix64(seed ~ splitmix64(step))`, then one mixer per draw,
  `splitmix64(root ~ (agent << 32 | use))`. There is no global generator and no state carried between draws.
- Every traversal is in insertion order or in the order a stable sort made: no map iteration, no address order.
- The tests: `the_same_seed_gives_the_same_run` compares every column of two runs of seed 42 after 200 steps;
  `another_seed_founds_another_world` checks that seeds 1 and 2 differ; `the_books_balance_at_every_step` runs three
  seeds for 400 steps and fails on the first step whose books do not balance.
- A future task system must keep this: the partition into blocks may change nothing, because no draw and no write
  depends on the order the blocks run in. That test does not exist yet (see ROADMAP).

## The books

Goods: `end == start + produced - consumed`. Money: `end == start`, because a trade moves money and creates none. Both are
in integers, so the check has no tolerance. `books_balanced` runs at the end of every step, as an assertion in the engine
and as a check in the command line.

## Performance

Measured on the author's machine, a release build, 64×64 cells:

| | |
|---|---|
| 1,000,000 people, sensors without the Gini | about 30 steps/s (30M agent-steps/s) |
| 1,000,000 people, the exact Gini every 10 steps | about 19 steps/s |
| 20,000 people | about 1,300 steps/s |

The budget is 33 ms a step for a million people. The pass count is what matters most: the first version had nine passes
(books open and close, two measure passes, eat and modulate apart) and gave 17 steps/s; merged, it gives about 30.

### What was measured and not kept

- A four-lane `core:simd` sum of the goods and money columns: 21 steps/s against 37 for the scalar loop. AVX2 wastes
  lanes on 64-bit integers, and the scalar reads the histogram still needs cost more than the vector loads save.
- The lesson is the project's rule: an optimization is measured before it is kept.

### What comes next

- Blocks of `BLOCK` agents for the regular phases (produce, eat, modulate, sums), so that a wider vector or the GPU can
  take a block. The irregular phases (markets, later networks) stay scalar.
- The GPU, if a measure says the regular phases dominate: the grid diffusion of fear or an epidemic is the natural
  first candidate, not the economy.

## Known limits

- One good, no labour market: money concentrates and the least productive starve. The next layer (firms, wages) is the
  fix, not a tuning of the constants.
- Deaths do not exist yet: a person at health 0 stays there. The columns are ready for a `dead` mask and a compaction
  the sort already provides.
- No threads: the step is single-threaded. The design's block rule and the pure-draw rule are what will let it scale to
  threads without changing a result.

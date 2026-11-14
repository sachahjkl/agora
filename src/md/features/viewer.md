# The viewer

The viewer is `src/viewer.odin`: a window over a world that runs beside it, and nothing else. It never reads the world
and never steps it. It reads a snapshot the engine thread publishes, and it draws.

## The thread

- `Sim` owns the world and a thread (`sim_run`). The thread steps the world at the rate asked (`rate`: 1, 10, 30 or 120
  a second), pauses on a flag, and sleeps the rest of a step.
- After every `SNAPSHOT_EVERY` steps it builds the map's sums (`engine.cells_snapshot`, one pass over the people), the
  per-market prices, the counters, and — every tenth step — the exact Gini and one point of the three charts.
- It then takes the lock and copies all of it into the published snapshot. The lock is held only for that copy, never
  during a step.
- The window copies the published snapshot at the start of each frame, under the same lock. The copy is bounded: a
  64×64 grid of four arrays, three series of 360 points. Nothing in a frame is proportional to the number of people.

This is the design's rule: the engine never waits for the viewer, the viewer never touches the world, and a slow frame
costs no step.

## What the window shows

- **The map**: one rectangle a cell, shaded by the layer chosen — **Land** (the river valley's fertility, the default),
  People (density), Hunger (mean per cell), Wealth (money per person). The scale is twice the mean of the layer, except
  hunger (against 60 of 100) and land (against 1000), so that a quiet world still reads.
- **The counters**: money per person, goods in the world, mean hunger, the share starving, mean health, the Gini of
  money, and the trades of the last step.
- **The charts**: the goods in the world, the mean hunger and the Gini, one point every ten steps, in a ring of 360 (two
  minutes at 30 steps a second).
- **The controls**: Pause/Play and the rate; the layer's buttons; the title says the step and the number of people.

## The look

The window wears the toolkit's own theme and finish: `ui.theme_show` with `Midnight` and `.Machined`, as every program
of the toolkit does, and `host` draws the frame. No colour of the interface is written in agora: only the data colours of
the map and the charts are, and they mean the data.

## Not there yet

- No inspector of one person, and no event log: the probe and the events of the sensors (`features/sensors.md`) come
  with the identity layer.
- No replay: a checkpoint every M steps, and a clock the viewer drives, are on the roadmap.
- The picture in the documentation is taken by `agoratool shot`, which runs the viewer with no window of the system,
  opens its DevTools endpoint and has the toolkit's `tk cdp` take the frame.

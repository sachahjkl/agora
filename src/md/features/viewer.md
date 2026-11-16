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

- **The map**: the ground drawn from its biome, its sea's depth and the slope's light (a west face is bright, an east face
  dark), then the layer chosen laid over it as a tint: **Land** (the ground, the default), People (density), Hunger (mean
  per cell), Wealth (money per person). The scale is twice the mean of the layer, except hunger (against 60 of 100). The
  biggest places are dots, with their names once the view is close; a chosen cell is ringed, and its people are drawn as
  dots inside it from a zoom of 4.
- **Moving in it**: the wheel zooms, a drag moves the view, a double click flies to a place, and the header's buttons do
  the same without a mouse (zoom out, zoom in, the whole world). The keyboard: Space pauses, + and − zoom, Home returns to
  the whole world.
- **Choosing a place**: a click on a cell selects it; the engine publishes its people (up to 24), the panel says its name,
  its ground, its people, its hunger and its market's price, and lists its people; a person chosen there has its own panel
  (money, goods, hunger, health, skill).
- **The header**: the mark, the step, the people and the goods; Pause/Play; the rate as a segmented control (×1, ×10,
  ×30, ×120).
- **The shell**: a top bar with the mark, the step, the people, the goods, the layers, the zoom and the world's clock
  (Pause/Play, ×1 to ×120); a sidebar with four tabs — *Place*, *World*, *News*, *Charts* — so that each fact has one
  place; a foot that says what the pointer does and which cell it is over.
- **The news**: as the world runs, a famine that starts and a place that fills with newcomers are written, with their
  step, into a ring of 24 lines that the *News* tab reads. The engine thread compares each step's cells with the last.
- **The legend**: the layer's name and its scale, over the map's lower left.
- **The panels**: *The world* (people, hunger, starving, Gini as figures; trades, goods, money per person and health as
  lines), *The biggest places* (the six most populated cells, with their biome, people, a hunger bar and their market's
  price), and *Over time* (three charts, each with its value now).
- **The look**: the toolkit's theme and finish (`Midnight`, `.Machined`), its cards, its segmented controls and its Lucide
  icons. No colour of the interface is written in agora: only the data colours of the map, the charts and the biome dots
  are, and they mean the data.

## Not there yet

- No inspector of one person, and no event log: the probe and the events of the sensors (`features/sensors.md`) come
  with the identity layer.
- No replay: a checkpoint every M steps, and a clock the viewer drives, are on the roadmap.
- The picture in the documentation is taken by `agoratool shot`, which runs the viewer with no window of the system,
  opens its DevTools endpoint and has the toolkit's `tk cdp` take the frame.

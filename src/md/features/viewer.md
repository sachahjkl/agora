# The viewer

The viewer is a window over a world that runs beside it, and nothing else. It never reads the world and never steps it.
It reads a snapshot the engine thread publishes, and it draws. Three files:

- `src/sim.odin`: the thread that steps the world, and the snapshot.
- `src/map.odin`: the map, drawn in one box.
- `src/viewer.odin`: the window around it (bar, tools, sidebar, foot, dialog).

## The thread

- `Sim` owns the world and a thread (`sim_run`). The thread steps the world at the rate asked (`rate`: 1, 10, 30 or 120
  a second), pauses on a flag, and sleeps the rest of a step.
- After every `SNAPSHOT_EVERY` steps it builds the map's sums (`engine.cells_snapshot`, one pass over the people), the
  per-market prices, the counters, the places, the means the layers are scaled against, the people of each ground, the
  news, and — every tenth step — the exact Gini and one point of each chart.
- It then takes the lock and copies all of it into the published snapshot. The lock is held only for that copy, never
  during a step.
- The window copies the published snapshot at the start of each frame, under the same lock. Nothing in a frame is
  proportional to the number of people. What a frame needs from the whole grid (a mean, a ranking) is computed by the
  thread when the world changes, never by the frame.
- **Another world** (`sim_found`): the window asks, the thread destroys its world and founds the new one before its next
  step. The founding takes a moment for a million people; on the thread it costs no frame. The new world has the size of
  the old one, so the snapshot's arrays stay.
- **`warm`**: steps the world lives before the thread starts and the window opens. It exists for the pictures of the
  documentation: a picture of a world of two steps shows flat layers and empty charts.

This is the design's rule: the engine never waits for the viewer, the viewer never touches the world, and a slow frame
costs no step.

## The map

- **One box, clipped.** Everything of the map (ground, houses, names, legend, overview) is drawn inside the box's
  rectangle, under a clip. An earlier version built the legend and the tools as boxes over the map; they went out of the
  frame. The tools (layers, zoom) are now a row above the frame, and the legend is drawn by the map itself.
- **A cell is a square.** `map_view` gives the side of a cell from the zoom: at zoom 1 the whole world fits in the box,
  whatever the box's shape, and is centred. The world is never stretched. Past the world's edge the last cell fades into
  the deep sea over `EDGE_FADE` cells, so the world has no border and no dark band.
- **One procedure for the view.** `map_view` is used by the drawing, by the pointer (`cell_at`) and by the zoom
  (`zoom_at` keeps the cell under the pointer where it is). The view is clamped inside the world there, once; a drag
  starts from the clamped centre (`map_centre`), so that a view pushed against an edge answers at once.
- **Levels of detail**, by the side of a cell on the screen:
  - far: one rectangle a cell, the biggest places as dots with their names;
  - from `SMOOTH_FROM`: the ground is blended between neighbours, a coast is a soft line;
  - from `HOUSES_FROM`: villages. A settled cell (more than `SETTLED` times the world's mean density) has houses, more
    as it is denser, filled from its middle; the country around has a farm here and there;
  - from `PEOPLE_FROM`: towns. A settled cell has two streets, with an arm towards each settled neighbour, and a house
    for each household; the chosen cell's people walk its streets, redder as they are hungrier, the chosen person ringed.
- **Why "settled".** People live on all the fertile land. Houses in proportion to people alone covered the land with a
  uniform pattern, and streets in every cell drew graph paper. The threshold makes places stand out of the country. It
  is a rule of the drawing only: the engine knows nothing of it.
- **A house keeps its lot.** Its place and its look are a hash of the cell and of its rank: nothing moves from frame to
  frame, and nothing is stored.
- **Places** (`is_peak`): a place is the most populated cell within `PLACE_REACH` cells. Without it the list of the
  biggest places was six neighbours of one town.
- **Layers**: Land (the ground alone), People, Hunger, Wealth, laid over the ground as a tint where people live. People
  and Wealth are scaled against twice the world's mean; Hunger against `HUNGER_FULL` of a hundred. The legend says the
  two ends.
- **The overview** appears once the view is closer than the whole world: the world, small, and the part shown.

## The window

- **The bar**: the mark, the world's headline numbers (step, people, starving, trades), its seed, *New world*, Pause/Run
  and the rate.
- **The sidebar**: four tabs, so that each fact has one place. *Place* (the chosen cell: its figures, its people, the
  chosen person), *World* (the world's figures, who lives on which ground, the biggest places), *News*, *Charts*.
  A row of the biggest places or of the news flies to its cell.
- **The foot**: what the pointer does, and the cell it is over.
- **The dialog** *A new world* is a view of the toolkit (`ui.view_register`): a seed and a number of people.
- **The news**: a famine that starts or ends, a place that fills or empties. A famine starts at `STARVING` and ends
  `FAMINE_EASE` under it, and a kind of event is quiet for `EVENT_QUIET` steps: a place that stays near the line was
  a famine and a relief at every step.
- **The look**: the toolkit's theme and finish (`Midnight`, `.Machined`), its cards, segmented controls, meters, graphs,
  dialogs and Lucide icons. No colour of the interface is written in agora: only the data colours of the map, of the
  charts and of the grounds are, and they mean the data.
- **Keys**: Space pauses, `=` and `-` zoom, Home shows the whole world, Escape drops the choice, 1 to 4 choose the layer.

## The pictures

`agoratool shot` takes the pictures of the documentation (`SHOT_VIEWS`): for each, it runs the viewer with no window of
the system (`--headless`), with the view asked on the command line (`--zoom`, `--select`, `--layer`, `--side`, `--person`,
`--dialog`, `--warm`), and has the toolkit's `tk cdp` take the frame through the DevTools endpoint. The endpoint answers
once the world has lived its `--warm` steps: the tool waits for that answer, not for a delay.

## Not there yet

- No interior of a house, and no firms: a house is a drawing of a household's count, not an object of the engine.
- No replay: a checkpoint every M steps, and a clock the viewer drives, are on the roadmap.
- A new world has the size of the old one.

# Roadmap

## Now

- **The viewer** — a window that draws the world from its sensors only: the map of a field, the series of the market, the
  inspector of one person. Intent: [features/simulation.md](src/md/features/simulation.md), "Viewer".

## Next

- **Firms and wages** — the labour market that lets money come back to the least productive, and turns the one-good
  economy's drift into a trade between employers and workers. Intent: [features/simulation.md](src/md/features/simulation.md),
  "Mechanisms that must emerge".
- **Determinism across blocks** — the same seed gives the same run with 1, 4 and 32 threads, once the step runs in
  blocks. Intent: [features/engine.md](src/md/features/engine.md), "Determinism".
- **The map, matrix, flow, event and probe sensors** — the sensor kinds the viewer needs beyond today's total, mean and
  Gini. Intent: [features/sensors.md](src/md/features/sensors.md), "What is not there yet".

## Later

- **Motivations and modulators** — subsistence, security, belonging and status, and the body and mind that change how a
  person decides. Intent: [features/simulation.md](src/md/features/simulation.md), "Motivations".
- **Identity, groups and borders** — abstract markers, learned trust, groups with leaders, states and war.
- **Epidemics and reproduction** — a disease on the contacts of the step, births and deaths, and a population that
  follows them.
- **Replay** — a checkpoint every M steps, and a viewer that goes back to any of them.

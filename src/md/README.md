# agora: intent

agora simulates a world of autonomous people and lets a person watch what emerges, live. The engine does the work; the
sensors measure it; the viewer, later, shows the measures and never the state.

The purpose is to observe and explain emergent phenomena, not to predict a real economy. That is why the model codes
motivations and mechanisms, never phenomena, and why every rule has a test that would catch it if it produced the
phenomenon directly.

## Overview

- `src/engine` is the engine: pure Odin, no window, advanced one step at a time. It is deterministic: a seed founds a
  world, and the same seed and options give the same run, byte for byte.
- The agents are columns (structure of arrays). Goods and money are 64-bit integers, so the books of every step balance
  to the unit.
- A step has five passes over the agents: sort by market and open the books, produce and state intentions, resolve the
  markets, eat and modulate, measure. Fewer passes is the first rule of performance.
- Sensors are the only observers: a reduction over a field, at its own rate, kept in a ring. A run with sensors and a
  run without them end in the same state.
- The viewer will read sensors only, through ring buffers, and will never touch the world.

## Subtleties

- **The seed is the initial condition.** Every draw is a pure function of the seed, the step, the agent and the use
  (`Rng_Key`), and the founding draws are separated by use, so the fields of one person are not correlated.
- **The books are integers.** Goods are centi-units and money its smallest unit. A division that would round is done on
  a quantity that is already an integer number of centi-units.
- **A SIMD sum was measured and kept out.** At 1,000,000 agents the four-lane version gave 21 steps/s against 37 for the
  scalar loop. The block layout stays ready for a wider vector or the GPU, when a measure says it pays.
- **Markets are regions**, 4×4 cells, so poor and rich land meet. One market per cell left every poor cell without a
  seller.
- **One good, no wages.** A closed one-good economy with fixed money concentrates money in the hands of the efficient
  producers: the inefficient sell nothing and starve. That is a real result, and the next layer (firms and a labour
  market) is what fixes it. The demo shows the drift; it does not pretend it is a cycle.
- **The exact Gini sorts the people.** It is a sensor with a rate (every tenth step by default), not a per-step cost.

## File Index

- [features/simulation.md](features/simulation.md): the model as designed — motivations, modulators, identity, groups,
  borders, war, sensors, viewer, and the build order.
- [features/engine.md](features/engine.md): the step as built — its passes, its determinism, its books, its measures.
- [features/sensors.md](features/sensors.md): the sensors as built, and the ones to come.
- [data/world.md](data/world.md): the columns, the units, the constants and the invariants.

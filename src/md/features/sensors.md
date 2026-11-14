# Sensors

A sensor is a declared reduction over a field of the agents, taken at its own rate, kept in a ring of samples. It is the
only way to observe a world: the viewer will read sensors, and nothing else.

## What a sensor is

```odin
Sensor :: struct {
	kind:   Sensor_Kind, // Total, Mean, Gini
	field:  Field,       // Goods, Money, Hunger, Health
	every:  u32,         // steps between two samples
	count:  int,
	next:   int,
	values: [SENSOR_SAMPLES]f64,
}
```

- `sensor_add(world, kind, field, every)` attaches one and returns its slot (a small integer, its identity).
- `sensor_latest`, `sensor_sample` and `sensor_history` read it; the viewer will read the same three.
- `Total` and `Mean` read the aggregates of the measure pass, computed once for every agent. `Gini` is exact: it copies
  the field into the scratch buffer and sorts it, so it is a sensor with a rate, never a per-step cost.
- A sensor changes nothing and draws no random number: `sensors_change_nothing` compares two runs of seed 9, one with
  four sensors, and fails if a single column differs.

## The ring

Each sensor keeps the last `SENSOR_SAMPLES` (512) values in a ring. A viewer that falls behind loses old samples and
knows it: `count` never exceeds the ring's size. The engine never waits for a reader.

## What is not there yet

The design (`features/simulation.md`, "Sensors") names map, matrix, flow, event and probe sensors. Each needs its own
storage and its own cost estimate:

- a **map** sensor: the per-cell fields have to be built in the measure pass (a grid of sums), then read as a picture;
- a **matrix** sensor (group × group): the identity layer must exist first;
- a **flow** (migration, exports): a sparse list of origin → destination pairs, with its own ring;
- an **event**: a timestamped list (a war declared, an epidemic started), kept beside the samples;
- a **probe**: one agent's whole state, at every step, for the inspector.

The rule for all of them is the same as today's: computed in the step's single measurement pass when it is a sum, off the
step when it is a sort, and never able to change the world.

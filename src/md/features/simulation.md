# Simulation: the model

agora simulates a world of autonomous agents in real time. The agents produce, trade, form groups, draw borders and go
to war. Sensors measure what emerges, and a viewer shows the measures live.

The goal is to observe and explain emergent phenomena. The goal is not to predict the real economy. This distinction
drives most technical choices.

## Principle

The model codes motivations, not phenomena. A phenomenon such as discrimination, a business cycle or a war must emerge
from simple rules. A rule that produces a phenomenon directly is a design error.

```
state of the individual (health, disease, fatigue, fear, age, wealth...)
        |  modulation
        v
motivations (deficit, expectations, weights)
        |  choice of action
        v
individual behaviour  ->  interactions  ->  collective phenomena
        ^                                          |
        +------------- feedback --------------------+
```

The feedback loop is the core of the model. Without it, motivations are constants and the model is static.

## Irreducible constraints

1. Time is discrete. Each step reads the state at `t` and writes the state at `t+1`.
2. The engine is deterministic. The same seed and the same parameters give the same result, byte for byte, whatever
   the number of threads.
3. The engine is independent of the viewer. It runs headless, faster than real time.
4. Agents are many and simple. Complex behaviour comes from interactions.
5. Every phenomenon is measurable. A sensor computes an indicator for it.
6. Stocks and flows are consistent. Money and goods never appear or disappear by error.

## World

The world has layers. Each layer acts on the agents.

| Layer | Content | Effect on agents |
|---|---|---|
| Geography | cells, relief, climate, resources, coasts, rivers | transport cost, productivity, access to resources |
| Production | sectors, technologies, stocks, capital | income, specialisation, dependencies |
| Exchange | local markets, trade between regions, prices, money, credit | prices, flows, spread of shocks |
| Society | households, demography, migration, social networks | inequality, mobility, population movements |
| Identity | markers, culture, affiliations | cooperation, trust, homophily |
| Institutions | states, taxes, property rights, borders, treaties | rules, redistribution, conflict |

The base agents are households, firms, banks and states. Relations between agents are typed networks: employment,
supply, credit, kinship and friendship, alliance. Networks are first-class objects: the viewer shows them and the
sensors measure them.

## Identity

Each agent has an identity in four layers.

| Layer | Examples | Origin | Changes |
|---|---|---|---|
| Visible marker | abstract appearance | birth | never |
| Acquired markers | language, religion, cultural traits | family, neighbours | slowly |
| Assigned affiliation | nationality, citizenship | state | by decision (naturalisation, conquest) |
| Chosen affiliation | clan, party, guild, firm | membership | yes |

Markers are abstract (colour A, B, C; language 1, 2, 3). They never represent real groups. The model studies the
mechanism and reproduces no stereotype.

A group is a set of agents that share a marker, or an institution with members, resources and rules. The engine uses
one structure for both.

## Motivations

The model starts with four motivations and adds the others one at a time.

| Motivation | Satisfied by | Frustrated by |
|---|---|---|
| Subsistence | food, income, shelter | shortage, unemployment |
| Security | stability, protection, predictability | violence, threat, uncertainty |
| Belonging | ties, group, recognition by peers | isolation, exclusion |
| Status | relative rank, prestige, power | loss of rank, humiliation |
| Autonomy | control over one's life | constraint, domination |
| Fairness | reciprocity, punishment of cheaters | perceived injustice |
| Kin | children, relatives, transmission | threat to the family |
| Curiosity | novelty, learning, exploration | routine, stagnation |

Each motivation has three values. Each value changes at its own speed.

1. Deficit (fast, each step). It grows while the need is not met and falls when an action meets it.
2. Expectations (medium). The agent learns what an action gives, and with whom. Trust and prejudice live here.
3. Weight (slow, a life or a generation). It is the importance of the motivation for this agent: temperament and
   culture. Age, strong events, imitation and transmission to children change it.

The culture of a group is the distribution of the weights and expectations of its members. The model does not code
culture separately.

### Choice of action

At each step the agent does these steps:

1. It computes the urgency of each motivation: deficit times weight.
2. It estimates, for each possible action, the expected satisfaction of each motivation.
3. It draws an action with weights: often the best one, sometimes another (bounded rationality).

Actions are few and generic: work, trade, cooperate, cheat, join a group, leave a group, migrate, arm, attack, flee,
punish, have a child, explore. One action meets several motivations. Joining a militia meets security, belonging and
status, and it frustrates autonomy.

### Two paths of decision

- Instinct (fast path): fixed and conditioned reactions. Flee a threat, defend kin, avoid what hurt before, follow the
  group. It is cheap and often wrong.
- Deliberation (slow path): the computation above. It is more accurate, but it costs capacity.

The share of instinct grows with fear, stress, fatigue, pain and urgency. It falls with rest, education and security.
A population under stress decides more by instinct: it becomes more tribal and more suspicious. The model does not code
this effect: it follows from the computation.

## Modulators

A modulator is a value of the state of an individual that changes how the agent decides. A modulator does not decide.

Each modulator has the same form:

- a value per agent, in [0, 1];
- a dynamic: what makes it rise and fall;
- a list of effects on a closed set of decision parameters.

The decision parameters are: the deficit gain per motivation, the weight offset per motivation, the noise of
perception, the horizon, the risk aversion, the share of instinct, the capacities (work, combat, movement,
reproduction, learning) and the mask of possible actions.

Modulators are rows of tables, not code paths. A new modulator is a new row.

| Group | Modulators |
|---|---|
| Body | health, disease, injury, pain, fatigue, hunger, age |
| Mind | fear, chronic stress, trauma, mood, anger |
| Social position | wealth, education, social status, network, rights |

Disease has its own sub-model. Each agent has an epidemic state per disease: healthy, infected, sick, then recovered or
dead. Infection follows the real contacts of the step: work, trade, household, combat, migration.

A part of the parameters is innate and inherited with variation. The rest is acquired. The ratio between innate and
acquired is a parameter of the world.

## Mechanisms that must emerge

| Behaviour | Motivations | Condition |
|---|---|---|
| Tribalism | belonging, security | external threat, scarce resources |
| Prejudice | security, expectations generalised by marker | bad experiences, few contacts, crisis |
| Scapegoat | security, status | fall of income, need for a cause |
| Nationalism | belonging, status | a state that gives a collective status |
| State formation | security of members, status of leaders | collective protection cheaper than defence alone |
| War | status and subsistence of leaders, security of members | scarcity, wrong estimate of forces, past humiliation |
| Revolt | fairness, autonomy | perceived inequality, domination |
| Migration | subsistence, security | gap in conditions, ties at the destination |

A group has no motivation of its own. It has leaders, who are agents, and members. The decisions of the group are the
decisions of the leaders, under constraints: if the group no longer meets the needs of its members, they leave or
revolt.

Coupling with the economy:

- Trust between groups lowers the transaction cost. Low trust gives fewer trades and lower productivity.
- Homophily in hiring misallocates labour. The loss of productivity is measurable.
- A border raises the cost of trade.
- War destroys capital and labour, and moves production to arms.
- Diversity raises the number of ideas and the cost of coordination. The balance is a result, not an assumption.

Phenomena that validate the model (stylised facts): a Pareto distribution of wealth, business cycles without an
external shock, urban agglomeration, trade flows that follow the gravity model, regional specialisation, spatial
segregation, cultural convergence and polarisation, contagion of financial crises, migration that follows gaps in
income and cultural ties.

## Engine

### Budget

Each step must fit a fixed budget. Target to confirm:

| Agents | Steps per second | Budget per step |
|---|---|---|
| 1 million | 30 | 33 ms |
| 10 million | 5 | 200 ms |

The limit is memory bandwidth, not computation. One million agents with 128 bytes of hot state move about 256 MB per
step. The rule: a small hot state, and one pass per phase.

### Data

- Columns (structure of arrays). Each field is a contiguous array. A phase reads only the columns it needs.
- Quantisation. A modulator in [0, 1] is a `u8`. A motivation is a `u8` or an `f16`.
- Hot and cold state are separate.
- Money and goods are integers (`i64`, in minimal units). Conservation is exact.
- Stable identifiers are handles with a generation. Births and deaths do not break references.

### Computation

- SIMD with Odin's vector types (`#simd`, `core:simd`). The baseline is AVX2.
- The choice of action has no branch. The agent computes the utility of every action, then masks the impossible ones.
- Randomness is a pure function of `(seed, step, agent, use)`, with a counter-based generator. There is no shared
  state.
- The modulator tables are small dense matrices, applied to blocks of agents.

### Interactions

1. Spatial sort at each step. Agents are sorted by cell with a counting sort. Neighbours are contiguous in memory. The
   sort also compacts the holes that deaths leave.
2. Bounded partners. Each agent has at most K interactions per step. The cost is O(n·K).
3. Intentions, then resolution. Phase 1: each agent writes its intentions to a buffer. Phase 2: each cell resolves its
   intentions alone. There is no lock and no concurrent write.
4. Double buffer. A phase reads the state at `t` and writes the state at `t+1`.

### Scheduling

- A job system splits the state into blocks of about 4,096 agents.
- Reductions combine partial sums in a fixed order, independent of the number of threads.
- Several rates. Fast systems run at each step (deficits, modulators, trade). Slow systems run every N steps (weights,
  culture, transmission). State decisions run more rarely.
- Load smoothing. Agent `i` runs its slow update when `(step + i) % N == 0`.
- CPU first. If a regular phase (fear diffusion, epidemic on the grid) limits the speed, it moves to the GPU after a
  measure.

## Sensors

A sensor is a declared measure that a user attaches to the running simulation. Sensors are the only way to observe.
The viewer never reads the engine state directly.

A sensor has:

- a selection: all agents, a region, a group, a state, or a filter;
- a field: a column, or a simple expression on columns;
- a reduction: sum, mean, minimum, maximum, count, histogram, quantiles, map, matrix or flow;
- a rate: each step, or every N steps.

| Kind | Output | Example |
|---|---|---|
| Scalar | one value per measure | total output, Gini |
| Distribution | histogram or quantile sketch of fixed size | wealth distribution |
| Map | grid of values | fear per cell |
| Matrix | group × group | trust, trade |
| Flow | origin → destination | migration, exports |
| Event | timestamped list | declaration of war, start of an epidemic |
| Probe | full state of one agent | follow one person and their decisions |

Rules:

- A sensor changes nothing and draws no random number.
- Each sensor has an estimated cost. The engine refuses a sensor over the observation budget, or lowers its rate and
  says so.
- The engine fuses sensors that read the same columns into one vector pass at the end of the step.
- Each sensor writes to a single-producer single-consumer ring buffer. The engine never waits for the viewer.
- The user creates a sensor live: draw a zone on the map, choose a field.

State machine of a sensor: declared, active, paused, removed, and degraded (rate lowered by the budget).

## Viewer

- The interface thread does no simulation and no system call. It reads the ring buffers and draws.
- The engine publishes a compact snapshot of the agents (position and one colour value, about 8 bytes per agent) in a
  triple buffer. The viewer draws it with instanced rendering on the GPU.
- Each series keeps several resolutions (a min/max pyramid). The cost of a graph depends on its pixels, not on the
  length of its history.
- Panels: map, series, matrix, network, event log, probe of an agent.
- The engine has its own speed: pause, single step, ×1, ×10, as fast as possible.
- The engine writes a checkpoint every M steps. Determinism lets the viewer replay from a checkpoint to any step.

## Tests that break the design on day one

1. Determinism. The same seed gives the same state, byte for byte, with 1, 4 and 32 threads, over 10,000 steps.
2. Conservation. Financial assets equal liabilities at each step. Goods produced equal goods consumed, stored or
   destroyed. The test uses integers, so it has no tolerance.
3. Sensor neutrality. A run without sensors and a run with 200 sensors give the same final state.
4. Modulator neutrality. With every modulator at rest, the result is identical to the result without modulators.
5. Ablation. Without a motivation, the phenomena it causes vanish. Without belonging, no stable group forms. If a
   phenomenon survives, a hidden rule produces it.
6. No degeneracy. Over 1,000 seeds, no motivation dominates the others in every world.
7. Budget (opt-in, it measures time). One million agents: the median step and the 99th percentile stay under budget.

## Implicit state machines

- Simulation: configured, running, paused, finished; and replay.
- Firm: created, active, in difficulty, bankrupt or bought.
- Household member: active, unemployed, retired, dead; and migrating.
- Loan: granted, repaid or in default.
- Epidemic state: healthy, infected, sick, recovered or dead.
- Relation between states: neutral, treaty, tension, war.
- Sensor: declared, active, paused, degraded, removed.

## Build order

1. Performance skeleton: state in columns, spatial sort, intentions and resolution, counter-based randomness, job
   system. Agents only move and trade. Determinism and conservation tests. Budget measure.
2. Sensors: scalar, map, distribution. Ring buffers. Sensor neutrality test.
3. Viewer: map of the agents, multi-resolution series, time control.
4. Four motivations and five modulators (health, hunger, fear, fatigue, wealth), in SIMD. Modulator neutrality test.
5. Instinct path. Sensor for the share of instinct.
6. Learned expectations and trust per marker. Matrix sensors.
7. Disease and infection through contacts.
8. Slow rates: weights, culture, transmission.
9. Groups, leaders, territory, conflict. Event and flow sensors.
10. Checkpoints and replay.
11. The other motivations and modulators, one at a time, each with its ablation test.
12. Distorted perception and propaganda.

Step 1 comes before any content. If the skeleton does not meet the budget with agents that do almost nothing, no
mechanism added later will meet it.

## Open decisions

- Target scale: number of agents and steps per second.
- Length of a step: a day for modulators, slower systems for culture and states.
- Unit of agent: individual, household, or both at two scales.
- Space: square grid, hexagons, or a graph of regions.
- Learning of expectations: a moving average (recommended first) or reinforcement learning.
- Inheritance of weights: genetic, cultural, or both.
- Format of sensors and modulator tables: one file format for code, files and the viewer.
- GPU surface in gui_toolkit for the map and the agents: check the toolkit before the viewer.

## Prior work

- Schelling, segregation model.
- Axelrod, dissemination of culture.
- Hammond and Axelrod, evolution of ethnocentrism.
- Epstein and Axtell, Sugarscape; Epstein, Agent_Zero.
- Turchin, cliodynamics and asabiya.
- Cederman, GeoSim (state formation and war).
- Richardson, arms races; Fearon, rationalist explanations for war; Olson, the stationary bandit.
- Dörner, PSI theory; Deci and Ryan, self-determination theory; Haidt, moral foundations.
- Stock-flow consistent models (Godley and Lavoie); EURACE; Krugman, new economic geography.
- Data for later calibration: Natural Earth, Penn World Table, WIOD, EXIOBASE, BACI, World Values Survey, UN World
  Population Prospects.

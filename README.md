<p align="center"><img src="assets/logo_128.png" alt="" width="96" height="96"></p>

<h1 align="center">agora</h1>

<p align="center"><b>A living world of autonomous people, watched as it runs.</b></p>

agora simulates a world of people who work, trade, trust, distrust, form groups, draw borders and go to war. Each person
acts from a few motivations: subsistence, security, belonging, status. Their health, hunger, fear and wealth change how
they decide. Nothing else is written in: tribalism, prejudice, business cycles, states and wars emerge, or do not, from
these rules.

The world runs in real time. You place sensors on it, on a region, a group or one person, and watch their measures live:
output, inequality, trust between groups, fear, epidemics, borders, fronts.

**Status: design.** No version is published yet. The design and its build order are in [docs/design.md](docs/design.md).

## What it will do

- **A world in real time**: the target is one million agents at about 30 steps per second, on the processor, with SIMD.
- **Motivations, not scripts**: each agent weighs its needs, learns whom to trust, and decides by deliberation or by
  instinct. Stress moves it towards instinct.
- **Modulators**: health, disease, hunger, fatigue, fear, trauma, wealth, education and rights change how an agent
  decides, through one table of effects.
- **Groups and borders**: abstract markers, learned trust, groups with leaders, states, borders, war and conquest.
- **Sensors**: scalar, distribution, map, matrix, flow, event and probe; attached live, and free for the simulation:
  a run with sensors and a run without them end in the same state.
- **Replay**: the same seed gives the same world, byte for byte, whatever the number of threads; go back to any step.

## Build

The program is written in [Odin](https://odin-lang.org) on [gui_toolkit](https://github.com/sachahjkl/gui_toolkit), for
Linux first. See [docs/development.md](docs/development.md).

```sh
git clone --recurse-submodules https://github.com/sachahjkl/agora
cd agora
nix develop
./build.sh
```

## Licence

MIT. See [LICENSE](LICENSE).

# agora

A real-time simulation of autonomous agents (economy, groups, borders, war) with sensors and a viewer, in Odin, on the
`ext/gui_toolkit` submodule (collection `gt`).

Read first: [README.md](README.md), [src/md/README.md](src/md/README.md) (the intent), [docs/development.md](docs/development.md).

## Intent

This project follows <https://srcmd.org>. The intent of the simulation, of the engine, of the data model and of the
sensors is Markdown in `src/md`, near the code. Read [src/md/README.md](src/md/README.md) first. Change the intent before
the code and the tests; a change of design changes its intent file in the same commit. Documentation for a person who
runs the program stays in `docs/`.

## Build and test

Every step is a command of `tools/agoratool` (`help` lists them):

    odin run tools/agoratool -collection:gt=ext/gui_toolkit/src -out:build/agoratool -keep-executable -- <command>

- `build [release]` builds `build/agora` (`build.sh` / `build.bat` are shortcuts).
- `check`: `odin check -vet`, the unit tests, the changelog's fragments and `ROADMAP.md`, THIRD-PARTY-NOTICES, a release build.
- `test [names]` runs the tests; `bench [agents] [steps]` measures the engine alone (opt-in).
- `logo` draws the logo, `card` the sharing card; `site build`, `site check` make and check the site.
- `ship <patch|minor|major|x.y.z>` publishes a version; `package` and `notes` are the release workflow's.
- `nix develop` first (`flake.nix`). `nix build` builds the package.

## Roadmap

`ROADMAP.md`, next to `CHANGELOG.md`, holds the planned work: `# Roadmap`, then `## Now`, `## Next` and `## Later`, each
a list of entries that start with a bold summary, no dates; an entry links its intent file in `src/md` when a design
exists. When a work is done, its entry goes in the same commit as its changelog fragment. `agoratool check` reads it, as
it reads the changelog.

## Rules

- **The Odin standard library first, systematically.** Sort, search, containers, text, hashing, time, math, JSON: use
  `core:*` (and `base:*`) rather than a hand-written version, unless a measured need or determinism says otherwise. Say
  why in a comment when the standard library is not used.
- Build in the roadmap's order: the performance skeleton, then sensors, then the viewer, then the mechanisms one at a
  time, each with its sensor and its test.
- The model codes motivations and modulators, never phenomena. A rule that produces a phenomenon directly is a bug.
- The engine is deterministic: the same seed gives the same state, byte for byte, whatever the number of threads.
  Randomness is a pure function of (seed, step, agent, use). Money and goods are integers.
- The engine never waits for the viewer. The viewer reads sensors only, through ring buffers, and never the state.
- A sensor changes nothing and draws no random number.
- **Phases run in blocks** (`BLOCK` agents), so that a phase can be vectorized with `core:simd` and, when a measure says
  it pays, moved to the GPU. A regular phase (production, eating, modulators, sums) is the SIMD or GPU candidate; the
  irregular ones (markets, networks) stay scalar. An optimization is measured before it is kept: `agoratool bench`.
- Markers of identity are abstract. They never name or depict a real group.
- What more than one program needs goes in gui_toolkit, generic, with its docs, test and changelog fragment; agora then
  points to the toolkit's new tag.
- A change a user can see is a fragment of `changelog.d/` (`agoratool changelog new`, its README), in the same commit;
  `CHANGELOG.md` is never edited by hand: `ship` assembles the fragments.
- Automation is a command of `tools/agoratool`, never a shell, batch, PowerShell, Python or Node script.
- Comments and commit messages are in English. Comments say why.
- Commits: author and committer `sachahjkl <sacha@sacha.house>`, no attribution trailer, no session link.

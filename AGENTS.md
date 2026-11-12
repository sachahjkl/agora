# agora

A real-time simulation of autonomous agents (economy, groups, borders, war) with sensors and a viewer, in Odin, on the
`ext/gui_toolkit` submodule (collection `gt`).

Read first: [README.md](README.md), [docs/design.md](docs/design.md), [docs/development.md](docs/development.md).

## Build and test

Every step is a command of `tools/agoratool` (`help` lists them):

    odin run tools/agoratool -collection:gt=ext/gui_toolkit/src -out:build/agoratool -keep-executable -- <command>

- `build [release]` builds `build/agora` (`build.sh` / `build.bat` are shortcuts).
- `check`: `odin check -vet`, the unit tests, the changelog's fragments, a release build.
- `logo` draws the logo and the sharing card; `site build`, `site check` make and check the site.
- `nix develop` first (`flake.nix`). `nix build` builds the package.

## Rules

- The design is [docs/design.md](docs/design.md). Build in its order: the performance skeleton first, then sensors, then
  the viewer, then the mechanisms one at a time, each with its sensor and its test.
- The model codes motivations and modulators, never phenomena. A rule that produces a phenomenon directly is a bug.
- The engine is deterministic: the same seed gives the same state, byte for byte, whatever the number of threads.
  Randomness is a pure function of (seed, step, agent, use). Money and goods are integers.
- The engine never waits for the viewer. The viewer reads sensors only, through ring buffers, and never the state.
- A sensor changes nothing and draws no random number.
- Markers of identity are abstract. They never name or depict a real group.
- What more than one program needs goes in gui_toolkit, generic, with its docs, test and changelog fragment; agora then
  points to the toolkit's new tag.
- A change a user can see is a fragment of `changelog.d/` (`agoratool changelog new`, its README), in the same commit;
  `CHANGELOG.md` is never edited by hand: `ship` assembles the fragments.
- Automation is a command of `tools/agoratool`, never a shell, batch, PowerShell, Python or Node script.
- Comments and commit messages are in English. Comments say why.
- Commits: author and committer `sachahjkl <sacha@sacha.house>`, no attribution trailer, no session link.

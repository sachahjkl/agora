# Development

## Setup

```sh
git clone --recurse-submodules <this repository>
cd agora
nix develop        # the pinned Odin with wgpu-native, Rust, the git hooks
```

Without Nix: Odin `dev-2026-11a` (`odin.version`), clang and lld, cargo (the toolkit's text library), wgpu-native's static
library in Odin's `vendor/wgpu/lib` (`odin run ext/gui_toolkit/tools/tk -- fetch_wgpu`), fontconfig.

## agoratool

Every step is a command of `tools/agoratool`, on the toolkit's tool library (`gt:toolbox`, its `docs/toolbox.md`).
`./build.sh` is its shortcut for `build`.

```sh
odin run tools/agoratool -collection:gt=ext/gui_toolkit/src -out:build/agoratool -keep-executable -- help
```

| Command | What it does |
|---|---|
| `build [release]` | the toolkit's text library (when its sources changed), then `build/agora` |
| `test [names]` | the tests of `src` and `src/engine` |
| `check` | `odin check -vet` of the program and the tool, the tests, the changelog's fragments and `ROADMAP.md`, THIRD-PARTY-NOTICES up to date, a release build |
| `bench [agents] [steps]` | the engine alone, a release build: its steps per second (opt-in: it measures time) |
| `logo` | `assets/logo*.png`, `.project/image.png` and `site/img/logo.png`, drawn by the toolkit's paint package |
| `card` | `site/img/card.png`, the sharing card |
| `shot [file]` | a picture of the viewer, with no window of the system: the offscreen window, its DevTools endpoint, and `tk cdp shot` |
| `package`, `notes`, `ship` | the release's archive and SHA-256; the changelog's section; a version from a clean `master` (`gt:release`) |
| `changelog new <type> <text> [-subject:…]`, `check`, `preview` | a fragment of `changelog.d/` (`gt:changelog`) |
| `site build <site> <out>`, `site check` | the site's pages; the pages in a real browser (`gt:site`) |

`GT=<folder>` builds against another checkout of gui_toolkit.

## The program

```sh
build/agora                                     # the window
build/agora run [--agents:N] [--steps:N] [--seed:N] [--every:N] [--gini-every:N] [--quiet]   # headless
```

The window runs the world in a thread and draws it from the snapshot the thread publishes (`src/viewer.odin`, its intent
is [src/md/features/viewer.md](../src/md/features/viewer.md)): `--agents`, `--rate`, `--seed`, and `--headless` for the
DevTools endpoint with no window of the system. The headless run prints the world's report; `--gini-every:0` turns the
exact Gini off, which is what the bench does (it sorts every person). The engine is in `src/engine`; its intent is
[src/md/features/engine.md](../src/md/features/engine.md).

## A change

- Comments and commit messages are in English. Comments say why.
- The design changes in `src/md` before the code; the code and its tests follow in the same commit.
- A test of the engine is deterministic: a seed, a number of steps, a condition. It never waits for a fixed delay. A test
  that measures time is opt-in (`bench`).
- What another program could use goes in gui_toolkit, generic, with its documentation, its test and its changelog
  fragment; agora then points to the toolkit's new tag.
- Write what a user sees changed as a fragment of `changelog.d/` (`agoratool changelog new <type> <text>`;
  `changelog.d/README.md`). Never edit `CHANGELOG.md`: `ship` assembles the fragments into the version's section. A
  finished work also leaves `ROADMAP.md` in the same commit.

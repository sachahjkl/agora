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

Every step is a command of `tools/agoratool`, on gui_toolkit's `gt:toolbox` (its `tool_main` and standard commands). `./build.sh` is its shortcut for `build`.

```sh
odin run tools/agoratool -collection:gt=ext/gui_toolkit/src -out:build/agoratool -keep-executable -- help
```

| Command | What it does |
|---|---|
| `build [release]` | the toolkit's text library (when its sources changed), then `build/agora` |
| `test` | the unit tests of `src` |
| `check` | `odin check -vet` of the program (Linux and Windows) and the tool, the scopes of `src`, the tests, the changelog's fragments, a release build |
| `logo` | `assets/logo*.png`, `.project/image.png`, `site/img/logo.png` and the sharing card `site/img/card.png`, drawn by the toolkit's paint package |
| `package [version]`, `notes <version>`, `ship <patch\|minor\|major\|x.y.z> [--dry-run]` | the release's archive and its SHA-256; the changelog's section; the release itself from a clean checkout, after `check` (gui_toolkit's `gt:release` and `gt:changelog`) |
| `changelog new <type> <text> [-subject:<subject>]`, `check`, `preview` | a fragment of `changelog.d/`; all of them well formed; what the next version brings |
| `site build <site> <out>`, `check`, `card` | the site's pages (from the first version: the site lists the versions); the pages in a real browser; `card` draws a card in a browser over `site/img/card.png`: agora does not use it, `logo` draws its card |

`GT=<folder>` builds against another checkout of gui_toolkit.

## A change

- Comments and commit messages are in English. Comments say why.
- The engine runs without a window. The viewer reads sensors only (see [design.md](design.md), "Sensors").
- A test of the engine is deterministic: a seed, a number of steps, a condition. It never waits for a fixed delay. A test
  that measures time is opt-in.
- What another program could use goes in gui_toolkit, generic, with its documentation, its test and its changelog
  fragment; agora then points to the toolkit's new tag.
- Write what a user sees changed as a fragment of `changelog.d/` (`agoratool changelog new <type> <text>`;
  `changelog.d/README.md`). Never edit `CHANGELOG.md`: `ship` assembles the fragments into the version's section.

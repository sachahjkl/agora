# Changelog

All notable changes to agora are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the versions follow [semantic versioning](https://semver.org/).

## [0.7.0] - 2026-11-16

### Added
- **A Windows version**: each release now has a Windows archive (`agora-<version>-windows-x64.zip`) beside the Linux one, and the site's download button offers both.
- **A new world from the window**: the bar's *New world* button opens a dialog that founds another world from a seed and a number of people (50 thousand to a million). The same seed always founds the same world.
- **Villages and towns on the map**: zoom in and the settled places show their houses, then their streets, a house for each household, and the people of the chosen place walking there, redder as they are hungrier. The country around keeps a farm here and there. The zoom now goes to ×24.

### Changed
- **The window is redone**: the map stays inside its frame and shows the whole world with no dark band; its layers and its zoom are a row above it, with an overview of the world once the view is close. The sidebar's four tabs fit their panel: a place's figures and its people with their hunger as bars, the world's figures and who lives on which ground, the news with a colour for each kind, and four charts.

### Fixed
- **The news no longer repeats itself**: a place whose hunger stays near the famine line is one famine, not a famine and a relief at every step; a relief and an exodus are news too, and a click on a line goes to its place. The list of the biggest places names distinct places, not the neighbours of one town.

## [0.6.0] - 2026-11-16

### Added
- **An application, not a sketch**: a bar carries the world's state, the layers, the zoom and the clock; the sidebar has four tabs (Place, World, News, Charts); a foot says what the pointer does; the map has its legend. The world writes its news as it runs: a famine that starts, a place that fills with newcomers.

## [0.5.1] - 2026-11-15

### Fixed
- **Two copies open at once no longer hide each other's crash**: when two copies of Agora ran at the same time, a crash or a forced end of one could go unreported, and its report could be hidden by the clean end of the other. Each copy now keeps its own trace, and the next start shows what it did not see.

## [0.5.0] - 2026-11-14

### Added
- **A world you can walk into**: the wheel zooms and a drag moves the map; a click chooses a place, another the person shown there. Cities are named, their people drawn as dots when the view is close, and the panels say what the ground gives, who starves and what the market asks. The engine answers the window with the chosen cell's people, and the map's layers, the pause, the rate and the zoom sit in one bar.

## [0.4.0] - 2026-11-14

### Added
- **A world, and the window over it**: continents, oceans, ice, deserts and mountains from the seed; hungry people move to better land as the world runs; and the window gains a framed map with zoom and pan, the figures of the world, the biggest places with their hunger, and charts with their values, in the toolkit's cards and icons. `agoratool shot` takes its picture with no window of the system.

## [0.3.0] - 2026-11-14

### Added
- **The window over the world**: the world now runs beside a window, in a thread, at 1 to 120 steps a second; the map shows the land, the people, the hunger or the wealth of every cell, with the counters and three charts from the sensors, and the window never touches the world. `agoratool shot` takes its picture with no window of the system.

## [0.2.0] - 2026-11-14

### Added
- **The engine runs a world**: a million people produce, trade and eat in a grid, five passes a step, with a seed that founds the world, books that balance to the unit and sensors that change nothing; about 30 steps/s at a million people. The intent is in src/md, the roadmap in ROADMAP.md.

## [0.1.0] - 2026-11-12

### Added
- **The design and the first skeleton**: the design of the simulation (motivations, modulators, groups and borders, sensors, the real-time engine and its build order), the logo and the site. The program only prints its version for now.

[0.7.0]: https://github.com/sachahjkl/agora/releases/tag/v0.7.0
[0.6.0]: https://github.com/sachahjkl/agora/releases/tag/v0.6.0
[0.5.1]: https://github.com/sachahjkl/agora/releases/tag/v0.5.1
[0.5.0]: https://github.com/sachahjkl/agora/releases/tag/v0.5.0
[0.4.0]: https://github.com/sachahjkl/agora/releases/tag/v0.4.0
[0.3.0]: https://github.com/sachahjkl/agora/releases/tag/v0.3.0
[0.2.0]: https://github.com/sachahjkl/agora/releases/tag/v0.2.0
[0.1.0]: https://github.com/sachahjkl/agora/releases/tag/v0.1.0

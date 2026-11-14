# Changelog

All notable changes to agora are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the versions follow [semantic versioning](https://semver.org/).

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

[0.5.0]: https://github.com/sachahjkl/agora/releases/tag/v0.5.0
[0.4.0]: https://github.com/sachahjkl/agora/releases/tag/v0.4.0
[0.3.0]: https://github.com/sachahjkl/agora/releases/tag/v0.3.0
[0.2.0]: https://github.com/sachahjkl/agora/releases/tag/v0.2.0
[0.1.0]: https://github.com/sachahjkl/agora/releases/tag/v0.1.0

// agoratool: the project's machinery, one program, whatever the shell.
//
//   odin run tools/agoratool -collection:gt=ext/gui_toolkit/src -out:build/agoratool -- <command>
//   (build.sh and build.bat are its shortcuts for `build`)
//
// What it needs is on the path: git, odin, cargo (the toolkit's text library).
// GT=<folder>: another checkout of gui_toolkit (its root, not its src). The dispatcher, the changelog's, the site's,
// the release's, the logo's and the notices' commands are the toolkit's (gt:toolbox, docs/toolbox.md).
package agoratool

import changelog "gt:changelog"
import release "gt:release"
import toolbox "gt:toolbox"

REPOSITORY :: "https://github.com/sachahjkl/agora"

// What agora is to its tool and to the toolkit's standard commands, and what Windows shows of it.
project :: proc() -> toolbox.Project {
	return {
		name = "agora", repository = REPOSITORY, changelog = "CHANGELOG.md",
		version_file = "src/main.odin", version_line = "APP_VERSION :: ", program = "build/agora",
		title = "Agora",
		description = "A world of autonomous people, simulated in real time and watched through sensors.",
		publisher = "Froment Software", copyright = "Copyright (c) 2026 sachahjkl",
	}
}

// What goes beside the program in a release's archive.
@(rodata)
RELEASE_FILES := [?][2]string{{"README.md", "README.md"}, {"LICENSE", "LICENSE"}, {"CHANGELOG.md", "CHANGELOG.md"}}

main :: proc() {
	p := project()
	r := release.commands({project = p, dist = "build/dist", files = RELEASE_FILES[:], check = proc() -> int { return run_check(nil) }})
	toolbox.tool_main(
		"agoratool",
		{
			{name = "build", usage = "[release]: the toolkit's text library when its sources changed, then build/agora", run = run_build},
			{name = "test", usage = "[names]: the tests of the program and of the engine", run = run_test},
			{name = "check", usage = ": odin check of the program and of this tool (-vet), the tests, the changelog and the roadmap, THIRD-PARTY-NOTICES up to date, then a release build", run = run_check},
			{name = "bench", usage = "[agents] [steps]: a release build, the steps per second of the engine alone (opt-in: it measures time)", run = run_bench},
			toolbox.logo_command(logo()),
			{name = "card", usage = ": site/img/card.png, the picture a shared link shows", run = run_card},
			{name = "shot", usage = "[file]: a picture of the viewer, in a sway nobody sees", run = run_shot},
			toolbox.notices_command(p),
			r[0],
			r[1],
			r[2],
			changelog.command(p),
			site_command(),
		},
		toolbox.ROOT_MARK_DEFAULT,
	)
}

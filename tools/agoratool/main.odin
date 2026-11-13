// agoratool: the project's machinery, one program, whatever the shell.
//
//   odin run tools/agoratool -collection:gt=ext/gui_toolkit/src -out:build/agoratool -keep-executable -- <command>
//   (build.sh and build.bat are its shortcuts for `build`)
//
// What it needs is on the path: git, odin, cargo (the toolkit's text library).
// GT=<folder>: another checkout of gui_toolkit (its root, not its src).
package agoratool

import changelog "gt:changelog"
import release "gt:release"
import tk_site "gt:site"
import toolbox "gt:toolbox"

REPOSITORY :: "https://github.com/sachahjkl/agora"

// What goes beside the program in the release's archive: the file, and its name there.
@(rodata)
DIST_FILES := [?][2]string{{"README.md", "README.md"}, {"LICENSE", "LICENSE"}, {"CHANGELOG.md", "CHANGELOG.md"}}

project :: proc() -> toolbox.Project {
	return {
		name = "agora", repository = REPOSITORY, changelog = "CHANGELOG.md",
		version_file = "src/main.odin", version_line = "APP_VERSION :: ",
		program = "build/agora",
	}
}

main :: proc() {
	p := project()
	r := release.commands({project = p, dist = "build/dist", files = DIST_FILES[:], check = proc() -> int { return run_check(nil) }})
	toolbox.tool_main("agoratool", {
		{name = "build", usage = "[release]: the toolkit's text library when its sources changed, then build/agora", run = run_build, checked = true, positionals = -1},
		{name = "test", usage = ": the unit tests of the program", run = run_test, checked = true},
		{name = "check", usage = ": odin check of the program (Linux and Windows) and of this tool (-vet), the scopes, the tests, the changelog's fragments, then a release build", run = run_check, checked = true},
		{name = "logo", usage = ": assets/logo*.png, .project/image.png, site/img/logo.png and the sharing card, drawn by the toolkit's paint package", run = run_logo, checked = true},
		changelog.command(p),
		tk_site.command({meta = site_meta(), pages = {version_mark = VERSION_MARK}}),
		r[0], r[1], r[2],
	}, toolbox.ROOT_MARK_DEFAULT)
}

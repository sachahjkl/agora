// agoratool: the project's machinery, one program, whatever the shell.
//
//   odin run tools/agoratool -collection:gt=ext/gui_toolkit/src -out:build/agoratool -keep-executable -- <command>
//   (build.sh and build.bat are its shortcuts for `build`)
//
// What it needs is on the path: git, odin, cargo (the toolkit's text library).
// GT=<folder>: another checkout of gui_toolkit (its root, not its src).
package agoratool

import "core:fmt"
import "core:os"
import "core:strings"
import toolbox "gt:toolbox"

EXIT_USAGE :: 2
ROOT_MARK  :: "odin.version"

Command :: struct {
	name, about: string,
	run:         proc(args: []string) -> int,
}

COMMANDS :: [?]Command{
	{name = "build", about = "[release]: the toolkit's text library when its sources changed, then build/agora", run = run_build},
	{name = "test", about = "the unit tests of the program", run = run_test},
	{name = "check", about = "odin check of the program and of this tool (-vet), the tests, the changelog's fragments, then a release build", run = run_check},
	{name = "logo", about = "assets/logo*.png, .project/image.png, site/img/logo.png and the sharing card, drawn by the toolkit's paint package", run = run_logo},
	{name = "package", about = "[version]: build/dist: the archive of a release build and its SHA-256", run = run_package},
	{name = "notes", about = "<version>: the changelog's section of that version", run = run_notes},
	{name = "ship", about = "<version> [--dry-run]: from a clean master, the fragments into the changelog, APP_VERSION, a commit, the tag, the push (the release workflow checks the tag)", run = run_ship},
	{name = "changelog", about = "new <type> <subject> <text> | check | preview: the fragments of changelog.d/, one per change a user can see", run = run_changelog},
	{name = "site", about = "build <site> <out> | check [--site folder] [--shot file.png] [--browser program]: the site's pages", run = run_site},
}

main :: proc() {
	if len(os.args) < 2 || os.args[1] == "help" || os.args[1] == "-h" || os.args[1] == "--help" { usage(); return }
	if !os.exists(ROOT_MARK) {
		root, code := toolbox.capture({"git", "rev-parse", "--show-toplevel"})
		if code != 0 { fmt.eprintln("agoratool: not in the repository"); os.exit(EXIT_USAGE) }
		if os.set_working_directory(strings.trim_space(root)) != nil { fmt.eprintfln("agoratool: cannot work in %s", root); os.exit(EXIT_USAGE) }
	}
	commands := COMMANDS
	for c in commands {
		if c.name == os.args[1] { os.exit(c.run(os.args[2:])) }
	}
	fmt.eprintfln("agoratool: no command %s", os.args[1])
	usage()
	os.exit(EXIT_USAGE)
}

usage :: proc() {
	fmt.println("agoratool <command> [arguments]")
	commands := COMMANDS
	for c in commands { fmt.printfln("  %-10s %s", c.name, c.about) }
}

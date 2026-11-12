package agoratool

// A release, the same steps on a laptop and in the release workflow, with the toolkit's (gt:release, gt:changelog):
//
//   package [version]       build/dist: agora-<version>-linux-x64.tar.gz (the program, its licence, the README and the
//                           changelog) and its SHA-256; a version given must be APP_VERSION
//   notes <version>         the changelog's section of that version (the notes of its GitHub release)
//   ship <version> [--dry-run]
//                           from a clean master: the fragments of changelog.d/ assembled into [<version>] with today's date,
//                           APP_VERSION set, a commit, the tag v<version>, the push. The release workflow checks the
//                           tag (agoratool check), builds the archive and publishes it; the site follows.
//   changelog new <type> <subject> <text> | check | preview
//                           a change a user can see is a fragment of changelog.d/ (docs/development.md), never an edit
//                           of CHANGELOG.md

import "core:fmt"
import changelog "gt:changelog"
import release "gt:release"

CHANGELOG    :: "CHANGELOG.md"
VERSION_FILE :: "src/main.odin"
VERSION_LINE :: "APP_VERSION :: "
REPOSITORY   :: "https://github.com/sachahjkl/agora"

// What goes beside the program in the archive: the file, and its name there.
@(rodata)
DIST_FILES := [?][2]string{{"README.md", "README.md"}, {"LICENSE", "LICENSE"}, {"CHANGELOG.md", "CHANGELOG.md"}}

release_config :: proc() -> release.Config {
	return {
		name = "agora", repository = REPOSITORY, changelog = CHANGELOG, version_file = VERSION_FILE, version_line = VERSION_LINE,
		// (no check of its own before the tag: the release workflow runs agoratool check on the tag, then builds)
		program = PROGRAM, dist = "build/dist", files = DIST_FILES[:],
	}
}

changelog_options :: proc() -> changelog.Options {
	return {root = ".", link = REPOSITORY + "/releases/tag/v%s"}
}

run_package :: proc(args: []string) -> int { return release.package_(release_config(), args) }

run_notes :: proc(args: []string) -> int { return release.notes(release_config(), args) }

run_ship :: proc(args: []string) -> int { return release.ship(release_config(), args) }

// `changelog new <type> <subject> <text>`: a fragment; `check`: every fragment well formed (check runs it); `preview`:
// what the next version brings.
run_changelog :: proc(args: []string) -> int {
	usage :: "agoratool changelog new <Added|Changed|Deprecated|Removed|Fixed|Security> <subject> <text> | check | preview"
	if len(args) == 0 { fmt.eprintln(usage); return EXIT_USAGE }
	switch args[0] {
	case "new":
		if len(args) != 4 { fmt.eprintln(usage); return EXIT_USAGE }
		path, why := changelog.new_fragment(".", args[1], args[2], args[3])
		if why != "" { fmt.eprintfln("agoratool: %s", why); return 1 }
		fmt.printfln("wrote %s", path)
	case "check":
		errors, fragments := changelog.check(changelog_options())
		for e in errors { fmt.eprintfln("agoratool: %s", e) }
		if len(errors) > 0 { return 1 }
		fmt.printfln("changelog: %d fragments, well formed", fragments)
	case "preview":
		text, errors := changelog.preview(".")
		for e in errors { fmt.eprintfln("agoratool: %s", e) }
		if len(errors) > 0 { return 1 }
		fmt.print(text == "" ? "nothing to release\n" : text)
	case:
		fmt.eprintln(usage)
		return EXIT_USAGE
	}
	return 0
}

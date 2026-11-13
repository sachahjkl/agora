package agoratool

// build, test, check: the program and its tests, with the odin commands the project (main.odin) makes.

import "core:fmt"
import "core:os"
import changelog "gt:changelog"
import toolbox "gt:toolbox"

run_build :: proc(args: []string) -> int {
	p := project()
	release := len(args) > 0 && args[0] == "release"
	if !toolbox.build_native(p) { return toolbox.EXIT_FAILED }
	_ = os.make_directory("build")
	extra := []string{fmt.tprintf("-out:%s", p.program), release ? "-o:speed" : "-debug"}
	if !toolbox.run(toolbox.odin_command(p, "build", extra = extra), {echo = true}) { return toolbox.EXIT_FAILED }
	fmt.printfln("built %s%s", p.program, release ? " (release)" : "")
	return toolbox.EXIT_DONE
}

run_test :: proc(args: []string) -> int {
	p := project()
	if !toolbox.build_native(p) { return toolbox.EXIT_FAILED }
	_ = os.make_directory("build")
	return toolbox.run(toolbox.odin_command(p, "test", extra = {"-out:build/test_agora"}), {echo = true}) ? toolbox.EXIT_DONE : toolbox.EXIT_FAILED
}

run_check :: proc(args: []string) -> int {
	p := project()
	if !toolbox.run(toolbox.odin_command(p, "check"), {echo = true}) { return toolbox.EXIT_FAILED }
	if !toolbox.run(toolbox.odin_command(p, "check", "tools/agoratool"), {echo = true}) { return toolbox.EXIT_FAILED }
	// (Windows code that does not compile fails here, on Linux, before a Windows build meets it)
	if !toolbox.check_windows(p) { return toolbox.EXIT_FAILED }
	if !toolbox.check_scopes("src") { return toolbox.EXIT_FAILED }
	if run_test(nil) != 0 { return toolbox.EXIT_FAILED }
	errors, fragments := changelog.check(changelog.project_options(&p))
	for e in errors { fmt.eprintfln("changelog: %s", e) }
	if len(errors) > 0 { return toolbox.EXIT_FAILED }
	fmt.printfln("changelog: %d fragments, well formed", fragments)
	return run_build({"release"})
}

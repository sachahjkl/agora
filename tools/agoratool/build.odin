package agoratool

// build, test, check, bench: the program and its tests, on the toolkit's toolbox.Project.

import "core:fmt"
import "core:os"
import "core:strings"
import changelog "gt:changelog"
import toolbox "gt:toolbox"

PROGRAM :: "build/agora"

// The packages that have tests, and this tool.
TEST_PACKAGES :: [?]string{"src", "src/engine"}

run_build :: proc(args: []string) -> int {
	p := project()
	release := len(args) > 0 && args[0] == "release"
	if !toolbox.build_native(p) { return 1 }
	_ = os.make_directory("build")
	extra := []string{"-out:" + PROGRAM, release ? "-o:speed" : "-debug"}
	if !toolbox.run(toolbox.odin_command(p, "build", "", extra), {echo = true}) { return 1 }
	fmt.printfln("built %s%s", PROGRAM, release ? " (release)" : "")
	return 0
}

run_test :: proc(args: []string) -> int {
	p := project()
	if !toolbox.build_native(p) { return 1 }
	_ = os.make_directory("build")
	// (names given, `agora.engine.test_name`: those tests alone, in that order)
	if len(args) > 0 {
		out := fmt.tprintf("-out:build/test_some")
		names := fmt.tprintf("-define:ODIN_TEST_NAMES=%s", args[0])
		return toolbox.run(toolbox.odin_command(p, "test", "", {out, names}), {echo = true}) ? 0 : 1
	}
	for pkg in TEST_PACKAGES {
		name, _ := strings.replace_all(pkg, "/", "_", context.temp_allocator)
		out := fmt.tprintf("-out:build/test_%s", name)
		if !toolbox.run(toolbox.odin_command(p, "test", pkg, {out}), {echo = true}) { return 1 }
	}
	return 0
}

run_check :: proc(args: []string) -> int {
	p := project()
	if !toolbox.run(toolbox.odin_command(p, "check"), {echo = true}) { return 1 }
	if !toolbox.run(toolbox.odin_command(p, "check", "tools/agoratool"), {echo = true}) { return 1 }
	if run_test(nil) != 0 { return 1 }
	// (the changelog's fragments and ROADMAP.md: the toolkit reads both)
	pp := p
	problems, fragments := changelog.check(changelog.project_options(&pp))
	for e in problems { fmt.eprintfln("agoratool check: %s", e) }
	if len(problems) > 0 { return 1 }
	fmt.printfln("changelog: %d fragments, well formed", fragments)
	if why := toolbox.third_party_notices(p, toolbox.NOTICES_FILE, check_only = true); why != "" {
		fmt.eprintfln("agoratool check: %s", why)
		return 1
	}
	return run_build({"release"})
}

// The engine alone, a release build: agents × steps, timed from the first step to the last. Opt-in: a loaded machine
// fails it for nothing.
run_bench :: proc(args: []string) -> int {
	agents := len(args) > 0 ? args[0] : "1000000"
	steps := len(args) > 1 ? args[1] : "200"
	if run_build({"release"}) != 0 { return 1 }
	return toolbox.run({PROGRAM, "run", fmt.tprintf("--agents:%s", agents), fmt.tprintf("--steps:%s", steps), "--seed:1", "--gini-every:0", "--quiet"}) ? 0 : 1
}

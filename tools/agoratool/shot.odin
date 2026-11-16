package agoratool

// shot: a picture of the viewer, taken without a window of the system. The program opens an offscreen window with its
// DevTools endpoint, runs a moment of world, and the toolkit's `tk cdp` takes the picture. Nothing of the person's
// desktop is opened or read.

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import toolbox "gt:toolbox"

// A picture of the documentation: its file in docs/screenshots, and what the window shows when it opens.
Shot_View :: struct {
	name: string,
	args: []string,
}

SHOT_PLACE :: "--select:32,82"
SHOT_WARM  :: "--warm:300"

SHOT_VIEWS := [?]Shot_View {
	{"viewer", {"--side:1"}},
	{"place", {"--zoom:7", SHOT_PLACE, "--person", "--side:0"}},
	{"town", {"--zoom:13", SHOT_PLACE, "--person", "--side:0"}},
	{"dialog", {"--dialog", "--side:1"}},
	{"hunger", {"--zoom:2.5", SHOT_PLACE, "--layer:2", "--side:3"}},
	{"people", {"--zoom:4", SHOT_PLACE, "--layer:1", "--side:2"}},
	{"wealth", {"--layer:3", "--side:1"}},
	{"close", {"--zoom:24", SHOT_PLACE, "--person", "--side:0"}},
}

// `shot`: every picture of the documentation. `shot <name>...`: those only.
run_shot :: proc(args: []string) -> int {
	if run_build({}) != 0 { return 1 }
	_ = os.make_directory_all("docs/screenshots")
	toolbox.guard_groups()
	for view, i in SHOT_VIEWS {
		wanted := len(args) == 0
		for a in args { if a == view.name { wanted = true } }
		if !wanted { continue }
		// (a port a view: the endpoint of the view before cannot answer for this one)
		if shot_view(view, fmt.tprintf("%d", 9333 + i)) != 0 { return 1 }
	}
	return 0
}

shot_view :: proc(view: Shot_View, port: string) -> int {
	out := fmt.tprintf("docs/screenshots/%s.png", view.name)
	env := toolbox.env_with(nil, fmt.tprintf("TOOLKIT_DEVTOOLS=%s", port))
	if driver := vulkan_driver(); driver != "" {
		more := make([]string, len(env) + 1, context.temp_allocator)
		copy(more, env)
		more[len(env)] = fmt.tprintf("VK_DRIVER_FILES=%s", driver)
		env = more
	}
	command := make([dynamic]string, context.temp_allocator)
	// (the world lives SHOT_WARM steps before its window opens: the charts, the news and the layers have something to
	// show, and the endpoint answers only then)
	append(&command, PROGRAM, "--headless", "--agents:200000", "--rate:30", SHOT_WARM)
	append(&command, ..view.args)
	process, err := toolbox.start_group(command[:], env, nil)
	if err != nil {
		fmt.eprintfln("agoratool shot: the viewer does not start")
		return 1
	}
	defer toolbox.stop_group(process)
	// the endpoint answers when the window is there: ask, with a bound
	endpoint := fmt.tprintf("http://127.0.0.1:%s/json", port)
	ready := false
	deadline := time.tick_now()
	for time.tick_since(deadline) < 120 * time.Second {
		code, _ := toolbox.capture({"curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", endpoint})
		if strings.trim_space(code) == "200" {
			ready = true
			break
		}
		time.sleep(200 * time.Millisecond)
	}
	if !ready {
		fmt.eprintln("agoratool shot: the DevTools endpoint did not answer")
		return 1
	}
	if !toolbox.run(
		{"odin", "run", "ext/gui_toolkit/tools/tk", "-out:build/tk", "--", "cdp", "--port", port, "idle", ",", "shot", out},
		{echo = true},
	) {
		fmt.eprintln("agoratool shot: the picture could not be taken")
		return 1
	}
	fmt.printfln("wrote %s", out)
	// the site shows the same pictures: its folder holds its own copies
	site_copy := fmt.tprintf("site/img/%s.png", view.name)
	if data, read_err := os.read_entire_file(out, context.temp_allocator); read_err == nil {
		_ = os.make_directory_all("site/img")
		if os.write_entire_file(site_copy, data) == nil { fmt.printfln("wrote %s", site_copy) }
	}
	return 0
}

// A Vulkan driver for the offscreen window, when the session names none: the software one (Mesa's lavapipe) beside the
// mesa the shell's LD_LIBRARY_PATH gives, else the system's own (NixOS's /run/opengl-driver). "" when neither is there:
// the program then says it has no adapter, as it would on a machine without Vulkan.
vulkan_driver :: proc() -> string {
	if os.get_env("VK_DRIVER_FILES", context.temp_allocator) != "" || os.get_env("VK_ICD_FILENAMES", context.temp_allocator) != "" { return "" }
	if paths := os.get_env("LD_LIBRARY_PATH", context.temp_allocator); paths != "" {
		rest := paths
		for dir in strings.split_iterator(&rest, ":") {
			candidate := fmt.tprintf("%s/../share/vulkan/icd.d/lvp_icd.x86_64.json", dir)
			if os.exists(candidate) { return candidate }
		}
	}
	system := "/run/opengl-driver/share/vulkan/icd.d"
	if os.exists(system) {
		files, err := os.read_all_directory_by_path(system, context.temp_allocator)
		if err == nil {
			for f in files {
				if strings.has_suffix(f.name, ".json") { return fmt.tprintf("%s/%s", system, f.name) }
			}
		}
	}
	return ""
}

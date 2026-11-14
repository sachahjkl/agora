package agoratool

// shot: a picture of the viewer, taken without a window of the system. The program opens an offscreen window with its
// DevTools endpoint, runs a moment of world, and the toolkit's `tk cdp` takes the picture. Nothing of the person's
// desktop is opened or read.

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import toolbox "gt:toolbox"

SHOT_FILE :: "docs/screenshots/viewer.png"
SHOT_PORT :: "9333"

run_shot :: proc(args: []string) -> int {
	out := len(args) > 0 ? args[0] : SHOT_FILE
	if run_build({}) != 0 { return 1 }
	_ = os.make_directory_all("docs/screenshots")
	toolbox.guard_groups()
	env := toolbox.env_with(nil, fmt.tprintf("TOOLKIT_DEVTOOLS=%s", SHOT_PORT))
	if driver := vulkan_driver(); driver != "" {
		more := make([]string, len(env) + 1, context.temp_allocator)
		copy(more, env)
		more[len(env)] = fmt.tprintf("VK_DRIVER_FILES=%s", driver)
		env = more
	}
	process, err := toolbox.start_group({"build/agora", "--headless", "--agents:400000", "--rate:240", "--zoom:5", "--select:32,82"}, env, nil)
	if err != nil {
		fmt.eprintfln("agoratool shot: the viewer does not start")
		return 1
	}
	defer toolbox.stop_group(process)
	// the endpoint answers when the window is there: ask, with a bound
	endpoint := fmt.tprintf("http://127.0.0.1:%s/json", SHOT_PORT)
	ready := false
	deadline := time.tick_now()
	for time.tick_since(deadline) < 20 * time.Second {
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
	// a moment of world before the picture: the charts have something to show
	time.sleep(2500 * time.Millisecond)
	if !toolbox.run(
		{"odin", "run", "ext/gui_toolkit/tools/tk", "-out:build/tk", "--", "cdp", "--port", SHOT_PORT, "wheel", "1150", "520", "6", ",", "idle", ",", "shot", out},
		{echo = true},
	) {
		fmt.eprintln("agoratool shot: the picture could not be taken")
		return 1
	}
	fmt.printfln("wrote %s", out)
	// the site shows the same picture: its folder holds its own copies
	site_copy := "site/img/viewer.png"
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

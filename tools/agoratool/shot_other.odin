#+build !linux
package agoratool

// shot, on a system other than Linux: the pictures of the documentation are taken on Linux (shot_linux.odin), where the
// toolbox starts the viewer in a group of processes and a software Vulkan driver draws it with no screen.

import "core:fmt"

run_shot :: proc(args: []string) -> int {
	fmt.eprintln("agoratool shot: the pictures are taken on Linux")
	return 1
}

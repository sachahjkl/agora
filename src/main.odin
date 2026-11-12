// agora: a world of autonomous agents, simulated in real time, watched through sensors.
// This is the skeleton: the engine and the viewer grow from here, in the order of docs/design.md, "Build order".
package agora

import "core:fmt"

APP_NAME    :: "agora"
APP_VERSION :: "0.1.0"

main :: proc() {
	fmt.printfln("%s %s", APP_NAME, APP_VERSION)
}

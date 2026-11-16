// agora: a world of autonomous people, simulated in real time and watched through sensors.
//
//   agora                     the window: the world runs beside it, in a thread, and sensors feed the map and the charts
//   agora run [options]       the engine alone, headless, with a report on the standard output
//   agora --frames:N          N frames of a hidden window, then exit (the check that the viewer runs)
//
// The seed founds the world: the same seed and the same options give the same run, byte for byte, on every machine.
package agora

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:time"
import engine "engine"

APP_NAME    :: "agora"
APP_VERSION :: "0.6.0"

Options :: struct {
	agents:     int,
	steps:      int,
	seed:       u64,
	width:      int,
	height:     int,
	every:      int,
	gini_every: int,
	rate:       int,
	frames:     int,
	headless:   bool,
	select:     string,
	zoom:       f32,
	layer:      int,  // the map's layer at the start: 0 land, 1 people, 2 hunger, 3 wealth
	side:       int,  // the sidebar's tab at the start: 0 place, 1 world, 2 news, 3 charts
	person:     bool, // the first person of the place chosen by --select is chosen too
	warm:       int,  // steps the world lives before the window opens
	dialog:     bool, // the dialog that founds another world is open from the start
	quiet:      bool,
}

DEFAULT_OPTIONS :: Options {
	agents     = 200_000,
	steps      = 1_000,
	seed       = 1,
	width      = 64,
	height     = 64,
	every      = 100,
	gini_every = 10,
	rate       = 30,
	frames     = -1,
	side       = 1,
}

usage :: proc() {
	fmt.printfln("%s %s", APP_NAME, APP_VERSION)
	fmt.println("agora                        the window, its world running beside it")
	fmt.println("agora run [options]          the engine alone, headless")
	fmt.println("  --agents:N      people in the world (200000)")
	fmt.println("  --steps:N       headless: steps to simulate (1000)")
	fmt.println("  --seed:N        the world's seed: the same seed gives the same run (1)")
	fmt.println("  --width:N       cells across (64)")
	fmt.println("  --height:N      cells down (64)")
	fmt.println("  --rate:N        the window's steps a second (30)")
	fmt.println("  --every:N       headless: print a line every N steps (100)")
	fmt.println("  --gini-every:N  the exact Gini every N steps; 0: never, the cheapest (10)")
	fmt.println("  --frames:N      N frames of a hidden window, then exit")
	fmt.println("  --headless      no window of the system (the picture through the DevTools endpoint)")
	fmt.println("  --select:X,Y    the window: a place chosen from the start; --person: its first person too")
	fmt.println("  --zoom:N        the window: the map's zoom at the start (1)")
	fmt.println("  --layer:N       the window: the map's layer (0 land, 1 people, 2 hunger, 3 wealth)")
	fmt.println("  --side:N        the window: the sidebar's tab (0 place, 1 world, 2 news, 3 charts)")
	fmt.println("  --dialog        the window: the dialog that founds another world is open from the start")
	fmt.println("  --warm:N        the window: steps the world lives before the window opens (0)")
	fmt.println("  --quiet         headless: the last line only")
}

main :: proc() {
	command := ""
	args := os.args[1:]
	if len(args) > 0 && args[0] == "run" {
		command = "run"
		args = args[1:]
	} else if len(args) > 0 && (args[0] == "version" || args[0] == "--version") {
		fmt.printfln("%s %s", APP_NAME, APP_VERSION)
		return
	} else if len(args) > 0 && (args[0] == "help" || args[0] == "--help" || args[0] == "-h") {
		usage()
		return
	} else if len(args) > 0 && args[0] != "--" && !has_prefix(args[0], "--") {
		fmt.eprintfln("agora: no command %s", args[0])
		usage()
		os.exit(1)
	}
	o := DEFAULT_OPTIONS
	if !parse(args, &o) {
		usage()
		os.exit(1)
	}
	if command == "run" {
		os.exit(run_headless(&o))
	}
	os.exit(viewer_run(&o))
}

has_prefix :: proc(s, p: string) -> bool {
	return len(s) >= len(p) && s[:len(p)] == p
}

// `--name:value` and `--name value`; a flag without a value is true.
parse :: proc(args: []string, o: ^Options) -> bool {
	i := 0
	for i < len(args) {
		arg := args[i]
		if arg == "--quiet" {
			o.quiet = true
			i += 1
			continue
		}
		if arg == "--headless" {
			o.headless = true
			i += 1
			continue
		}
		if arg == "--dialog" {
			o.dialog = true
			i += 1
			continue
		}
		if arg == "--person" {
			o.person = true
			i += 1
			continue
		}
		name, value, has_value := split_flag(arg)
		if !has_prefix(name, "--") {
			fmt.eprintfln("agora: unknown argument %s", arg)
			return false
		}
		if !has_value {
			if i + 1 >= len(args) {
				fmt.eprintfln("agora: %s wants a value", name)
				return false
			}
			value = args[i + 1]
			i += 1
		}
		ok := true
		switch name[2:] {
		case "agents":
			o.agents, ok = strconv.parse_int(value)
		case "steps":
			o.steps, ok = strconv.parse_int(value)
		case "seed":
			o.seed, ok = strconv.parse_u64(value)
		case "width":
			o.width, ok = strconv.parse_int(value)
		case "height":
			o.height, ok = strconv.parse_int(value)
		case "every":
			o.every, ok = strconv.parse_int(value)
		case "gini-every":
			o.gini_every, ok = strconv.parse_int(value)
		case "rate":
			o.rate, ok = strconv.parse_int(value)
		case "frames":
			o.frames, ok = strconv.parse_int(value)
		case "select":
			o.select = value
		case "zoom":
			o.zoom, ok = strconv.parse_f32(value)
		case "layer":
			o.layer, ok = strconv.parse_int(value)
		case "side":
			o.side, ok = strconv.parse_int(value)
		case "warm":
			o.warm, ok = strconv.parse_int(value)
		case:
			fmt.eprintfln("agora: unknown option %s", name)
			return false
		}
		if !ok {
			fmt.eprintfln("agora: %s is not a number: %s", name, value)
			return false
		}
		i += 1
	}
	return o.agents > 0 && o.steps >= 0 && o.width > 0 && o.height > 0 && o.every > 0 && o.rate > 0
}

@(private = "file")
split_flag :: proc(arg: string) -> (name, value: string, has_value: bool) {
	for i in 0 ..< len(arg) {
		if arg[i] == ':' {
			return arg[:i], arg[i + 1:], true
		}
	}
	return arg, "", false
}

run_headless :: proc(o: ^Options) -> int {
	w := engine.world_make({width = o.width, height = o.height, agents = o.agents, seed = o.seed})
	defer engine.world_destroy(&w)

	// The first sensors: the goods in the world, the money each person holds, and its inequality, taken every tenth
	// step (an exact Gini sorts the people, so it costs more than the others).
	goods := engine.sensor_add(&w, .Total, .Goods, 1)
	wealth := engine.sensor_add(&w, .Mean, .Money, 1)
	gini := 0
	if o.gini_every > 0 { gini = engine.sensor_add(&w, .Gini, .Money, u32(o.gini_every)) }
	hunger := engine.sensor_add(&w, .Mean, .Hunger, 1)

	if !o.quiet {
		fmt.printfln("%s %s", APP_NAME, APP_VERSION)
		fmt.printfln("world %dx%d, %d people, seed %d", o.width, o.height, o.agents, o.seed)
		fmt.println(engine.report_line(engine.report(&w)))
	}

	start := time.tick_now()
	for _ in 0 ..< o.steps {
		engine.world_step(&w)
		if !o.quiet && w.step % u64(o.every) == 0 {
			fmt.println(engine.report_line(engine.report(&w)))
		}
		if why := engine.books_why(&w); why != "" {
			fmt.eprintfln("agora: the books do not balance at step %d: %s", w.step, why)
			return 1
		}
	}
	elapsed := time.tick_since(start)
	seconds := time.duration_seconds(elapsed)
	rate := seconds > 0 ? f64(o.steps) / seconds : 0

	if !o.quiet {
		fmt.println()
		fmt.println(engine.report_line(engine.report(&w)))
		fmt.printfln(
			"sensors: goods %.0f, money per person %.1f, gini %.3f, hunger %.1f",
			engine.sensor_latest(&w, goods), engine.sensor_latest(&w, wealth), o.gini_every > 0 ? engine.sensor_latest(&w, gini) : 0, engine.sensor_latest(&w, hunger),
		)
		fmt.printfln("books: goods and money balance to the unit")
	}
	fmt.printfln("%.1f steps/s, %.1fM agent-steps/s", rate, rate * f64(o.agents) / 1e6)
	return 0
}

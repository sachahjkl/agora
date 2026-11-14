// agora: a world of autonomous people, simulated in real time and watched through sensors.
//
//   agora run [--agents:100000] [--steps:1000] [--seed:1] [--width:64] [--height:64] [--every:100] [--quiet]
//
// The seed founds the world: the same seed and the same options give the same run, byte for byte, on every machine.
// The engine does the work; the command line is its first observer, and the sensors' first reader.
package agora

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:time"
import engine "engine"

APP_NAME    :: "agora"
APP_VERSION :: "0.2.0"

Options :: struct {
	agents: int,
	steps:  int,
	seed:   u64,
	width:  int,
	height: int,
	every:  int,
	gini_every: int,
	quiet:  bool,
}

DEFAULT_OPTIONS :: Options {
	agents = 100_000,
	steps  = 1_000,
	seed   = 1,
	width  = 64,
	height = 64,
	every  = 100,
	gini_every = 10,
}

usage :: proc() {
	fmt.printfln("%s %s", APP_NAME, APP_VERSION)
	fmt.println("agora run [options]")
	fmt.println("  --agents:N    people in the world (100000)")
	fmt.println("  --steps:N     steps to simulate (1000)")
	fmt.println("  --seed:N      the world's seed: the same seed gives the same run (1)")
	fmt.println("  --width:N     cells across (64)")
	fmt.println("  --height:N    cells down (64)")
	fmt.println("  --every:N     print a line every N steps (100)")
	fmt.println("  --gini-every:N  take the exact Gini every N steps; 0: never, the cheapest (10)")
	fmt.println("  --quiet       the last line only (the steps per second)")
}

main :: proc() {
	if len(os.args) < 2 {
		usage()
		os.exit(1)
	}
	switch os.args[1] {
	case "run":
		os.exit(run(os.args[2:]))
	case "version", "--version", "-v":
		fmt.printfln("%s %s", APP_NAME, APP_VERSION)
	case "help", "--help", "-h":
		usage()
	case:
		fmt.eprintfln("agora: no command %s", os.args[1])
		usage()
		os.exit(1)
	}
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
		name, value, has_value := split_flag(arg)
		if len(name) < 2 || name[:2] != "--" {
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
	return o.agents > 0 && o.steps > 0 && o.width > 0 && o.height > 0 && o.every > 0
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

run :: proc(args: []string) -> int {
	o := DEFAULT_OPTIONS
	if !parse(args, &o) {
		usage()
		return 1
	}
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

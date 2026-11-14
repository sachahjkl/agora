// agora's engine: a world of agents in columns, advanced one step at a time.
//
// The step reads the state at t and writes the state at t+1 in fixed phases (world.odin). Randomness is a pure function
// of (seed, step, agent, use), so a run is the same whatever order the agents are visited in, and later whatever the
// number of threads. Money and goods are integers, and the books of every step balance exactly (books.odin).
package engine

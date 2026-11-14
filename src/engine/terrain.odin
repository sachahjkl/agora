package engine

// The world's ground: continents and oceans from fractal noise, a climate by latitude and moisture, biomes from both.
// Everything comes from the seed alone and is computed in pure Odin, so a world is the same on every machine.

import "core:math"

Biome :: enum u8 {
	Ocean,
	Ice,
	Tundra,
	Desert,
	Grass,
	Forest,
	Mountain,
}

// Per thousand: what a healthy, skilled person gets out of the cell. Ocean and ice give nothing, and nobody lives there.
BIOME_PRODUCTIVITY := [Biome]u16{
	.Ocean = 0,
	.Ice = 0,
	.Tundra = 320,
	.Desert = 240,
	.Grass = 900,
	.Forest = 820,
	.Mountain = 200,
}

// How high a cell sits, from 0 (the deepest sea) to 65535 (a summit); the viewer draws it in relief.
TERRAIN_SHADE :: 0.0 // (the terrain's own light is the viewer's; this constant is kept for scale documentation)

// A hash of a lattice point: splitmix64 over the two coordinates and the seed.
@(private = "file")
lattice :: proc(x, y: i64, seed: u64) -> u64 {
	return splitmix64(u64(x) * 0x9E3779B97F4A7C15 ~ u64(y) * 0xC2B2AE3D27D4EB4F ~ seed)
}

@(private = "file")
fade :: proc(t: f64) -> f64 { return t * t * t * (t * (t * 6 - 15) + 10) }

// Value noise: the lattice's values, smoothly interpolated, in [0, 1).
value_noise :: proc(x, y: f64, seed: u64) -> f64 {
	xi, yi := i64(math.floor(x)), i64(math.floor(y))
	fx, fy := x - f64(xi), y - f64(yi)
	u, v := fade(fx), fade(fy)
	at :: proc(ix, iy: i64, seed: u64) -> f64 { return f64(lattice(ix, iy, seed) >> 11) / f64(u64(1) << 53) }
	a := at(xi, yi, seed)
	b := at(xi + 1, yi, seed)
	c := at(xi, yi + 1, seed)
	d := at(xi + 1, yi + 1, seed)
	top := a + (b - a) * u
	bottom := c + (d - c) * u
	return top + (bottom - top) * v
}

// Fractal noise: octaves of value noise, each finer and weaker, in [0, 1).
fbm :: proc(x, y: f64, seed: u64, octaves: int) -> f64 {
	sum, amplitude, total := 0.0, 1.0, 0.0
	frequency := 1.0
	for o in 0 ..< octaves {
		sum += value_noise(x * frequency, y * frequency, seed ~ u64(o) * 0x100000001B3) * amplitude
		total += amplitude
		amplitude *= 0.5
		frequency *= 2.0
	}
	return sum / total
}

// The ground of a world: elevation, climate and biome per cell, and the land cells that can hold people.
terrain_generate :: proc(cells: []Cell, width, height: int, seed: u64) -> (land: [dynamic]u32) {
	assert(len(cells) == width * height)
	// the raw shape first, then stretched from its lowest point to its highest: fractal noise stays near its mean, and a
	// fixed sea level over it would drown the world
	raw := make([]f32, len(cells))
	defer delete(raw)
	lo, hi: f32 = 1e9, -1e9
	for y in 0 ..< height {
		for x in 0 ..< width {
			nx := f64(x) / f64(width)
			ny := f64(y) / f64(height)
			// continents: a broad mask in two noises, a broken coast, and a falloff toward the map's edges (a sea all around)
			continent := fbm(nx * 2.4 + 3.0, ny * 2.4 + 7.0, seed ~ 0x7F4A7C15, 3)
			broad := fbm(nx * 3.6, ny * 3.6, seed, 4)
			broken := fbm(nx * 8.5 + 11.7, ny * 8.5 + 3.1, seed ~ 0xB5297A4D, 3)
			dx, dy := (nx - 0.5) * 2, (ny - 0.5) * 2
			falloff := clamp(1.12 - (dx * dx + dy * dy) * 0.22, 0, 1)
			e := f32((continent * 0.55 + broad * 0.3 + broken * 0.15) * falloff)
			raw[y * width + x] = e
			lo = min(lo, e)
			hi = max(hi, e)
		}
	}
	if hi <= lo { hi = lo + 1 }

	for y in 0 ..< height {
		for x in 0 ..< width {
			c := y * width + x
			elevation := clamp((raw[c] - lo) / (hi - lo), 0, 1)
			// climate: colder toward the poles, with noise; moisture from another noise, drier inland
			nx := f64(x) / f64(width)
			ny := f64(y) / f64(height)
			temperature := clamp(1.0 - math.abs(f64(y) - f64(height) * 0.5) / (f64(height) * 0.5), 0, 1)
			temperature = clamp(temperature + (fbm(nx * 2.7, ny * 2.7, seed ~ 0x68E31DA4, 2) - 0.5) * 0.25, 0, 1)
			moisture := clamp(fbm(nx * 4.0 + 5.0, ny * 4.0 + 9.0, seed ~ 0x1B56C4E9, 3) * 1.25 - 0.1, 0, 1)

			biome := Biome.Grass
			if elevation < 0.50 {
				biome = .Ocean
			} else if temperature < 0.16 {
				biome = .Ice
			} else if elevation > 0.86 {
				biome = .Mountain
			} else if temperature < 0.30 {
				biome = .Tundra
			} else if moisture < 0.34 {
				biome = .Desert
			} else if moisture > 0.58 {
				biome = .Forest
			}
			cells[c] = {
				productivity = BIOME_PRODUCTIVITY[biome],
				elevation    = u16(elevation * 65535),
				biome        = biome,
				temperature  = u8(temperature * 255),
				moisture     = u8(moisture * 255),
			}
		}
	}

	// the coast: land next to the sea is richer (fish, harbours)
	for y in 0 ..< height {
		for x in 0 ..< width {
			c := y * width + x
			if cells[c].biome == .Ocean || cells[c].biome == .Ice { continue }
			coastal := false
			for d in ([4][2]int{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) {
				nx, ny := x + d[0], y + d[1]
				if nx < 0 || ny < 0 || nx >= width || ny >= height { continue }
				if cells[ny * width + nx].biome == .Ocean { coastal = true }
			}
			if coastal && cells[c].productivity > 0 { cells[c].productivity += 180 }
		}
	}

	for c in 0 ..< len(cells) {
		if cells[c].productivity > 0 { append(&land, u32(c)) }
	}
	return
}

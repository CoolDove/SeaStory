package main

import "core:fmt"
import "core:math/rand"
import "core:math/noise"
import "core:math/linalg"
import rl "vendor:raylib"


Bird :: struct {
	hitpoint : int,
	pos : rl.Vector2,
	destination : rl.Vector2,
	dest_time : f64,
	level : int,
	shoot_interval : f32,
	shoot_colddown : f32
}

BirdGenerator :: struct {
	interval : f64,
	time : f64,// ms
}
birdgen_update :: proc(g: ^Game, bg: ^BirdGenerator, delta: f64) {
	bg.time += delta
	if bg.time >= bg.interval {
		x := cast(f32)(rand.uint32()%BLOCK_WIDTH)
		y := cast(f32)(rand.uint32()%BLOCK_WIDTH)
		game_add_birds(g, {x,y})
		bg.time = 0
	}
}

bird_update :: proc(b: ^Bird, g: ^Game, delta: f64) {
	if b.dest_time == 0 {
		if len(g.land) == 0 do return
		i := rand.uint32()%(auto_cast len(g.land))
		x := g.land[i].x
		y := g.land[i].y
		b.destination = {auto_cast x, auto_cast y}
		b.dest_time = g.time
	}
	if b.dest_time != 0 {
		dir := linalg.normalize(b.destination - b.pos)
		step := 2*auto_cast delta
		if auto_cast linalg.distance(b.destination, b.pos) < step {
			// fmt.printf("i'm attacking...\n")
			target :[2]int= {auto_cast b.destination.x, auto_cast b.destination.y}
			idx := get_index(target.x, target.y)
			if g.hitpoint[idx] > 0.0 {
				g.hitpoint[idx] -= cast(f32)(1.0/5.0 * delta)
				if g.hitpoint[idx] <= 0.0 {
					g.mask[idx] = 0
					b.dest_time = 0
				}
			}
		} else {
			b.pos += dir * 2 * auto_cast delta
		}
	}
}

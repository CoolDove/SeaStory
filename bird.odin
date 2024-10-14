package main

import "core:fmt"
import "core:math/rand"
import "core:math/noise"
import "core:math/linalg"
import rl "vendor:raylib"


Bird :: struct {
	hitpoint : int,
	pos : Vec2,
	target : Vec2i,
	destination : Vec2,
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
		from := [2]int{auto_cast (rand.uint32()%BLOCK_WIDTH), auto_cast (rand.uint32()%BLOCK_WIDTH)}
		buffer : [BLOCK_WIDTH*BLOCK_WIDTH]u32
		if pos, ok := find_empty_cell(g, from, &buffer); ok {
			x := cast(f32)pos.x
			y := cast(f32)pos.y
			game_add_bird(g, {x,y})
		}
		bg.time = 0
	}
}

find_empty_cell :: proc(g: ^Game, from: [2]int, buffer: ^[BLOCK_WIDTH*BLOCK_WIDTH]u32, dir:u32=0xff) -> ([2]int, bool) {
	DIR_NONE :: 0
	DIR_ROOT :: 0xff
	DIR_UP :: 1
	DIR_DOWN :: 2
	DIR_LEFT :: 3
	DIR_RIGHT :: 4
	if !in_range(from.x, from.y) do return {}, false
	idx := get_index(from.x, from.y)
	buffer[idx] = dir
	if g.mask[idx] == 0 do return from, true
	if tup := from+{0,1}; in_range(tup.x, tup.y) && buffer[get_index(tup.x, tup.y)] != DIR_NONE {
		if up, up_ok := find_empty_cell(g, from+{0,1}, buffer); up_ok do return up, true
	}
	if tdown := from+{0,1}; in_range(tdown.x, tdown.y) && buffer[get_index(tdown.x, tdown.y)] != DIR_NONE {
		if down, down_ok := find_empty_cell(g, from+{0,1}, buffer); down_ok do return down, true
	}
	if tleft := from+{0,1}; in_range(tleft.x, tleft.y) && buffer[get_index(tleft.x, tleft.y)] != DIR_NONE {
		if left, left_ok := find_empty_cell(g, from+{0,1}, buffer); left_ok do return left, true
	}
	if tright := from+{0,1}; in_range(tright.x, tright.y) && buffer[get_index(tright.x, tright.y)] != DIR_NONE {
		if right, right_ok := find_empty_cell(g, from+{0,1}, buffer); right_ok do return right, true
	}
	return {}, false
}

bird_update :: proc(b: ^Bird, g: ^Game, delta: f64) {
	if b.dest_time == 0 {
		if len(g.land) == 0 do return
		i := rand.uint32()%(auto_cast len(g.land))
		x := g.land[i].x
		y := g.land[i].y
		b.target = g.land[i]
		b.destination = {auto_cast x + rand.float32()*0.1, auto_cast y}
		b.dest_time = g.time
	}
	if b.dest_time != 0 {
		dir := linalg.normalize(b.destination - b.pos)
		step := 2*auto_cast delta
		if auto_cast linalg.distance(b.destination, b.pos) < step {
			target :Vec2i= {auto_cast b.destination.x, auto_cast b.destination.y}
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

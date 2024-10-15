package main

import "core:fmt"
import "core:math/rand"
import "core:math/noise"
import "core:math/linalg"
import rl "vendor:raylib"
import hla "collections/hollow_array"

BirdHandle :: hla.HollowArrayHandle(Bird)
Bird :: struct {
	hitpoint : int,
	pos : Vec2,
	target : Vec2i,
	speed : f64,
	destination : Vec2,
	dest_time : f64,
	level : int,
	attack : int,// how much damage one shoot
	shoot_interval : f64,
	shoot_colddown : f64
}

BirdGenerator :: struct {
	wave : BirdWave,
	time : f64,// ms
}

BirdWave :: struct {
	count : int,
	time : f64,
	born : rl.Rectangle,
	target : rl.Rectangle,
}

birdgen_update :: proc(g: ^Game, bg: ^BirdGenerator, delta: f64) {
	bg.time += delta
	using bg
	if wave.time > 0 {
		wave.time -= delta
		if wave.time <= 0 {
			for i in 0..<wave.count {
				pos :Vec2= {rand.float32()*wave.born.width+wave.born.x, rand.float32()*wave.born.height+wave.born.y}
				game_add_bird(g, pos)
			}
			wave.time = 0
		}
	}
	if wave.time == 0 {
		wave.time = auto_cast (rand.int31()%5+7)
		wave.count = auto_cast (rand.int31()%4+4)
		x := cast(f32)(rand.int31()%cast(i32)(BLOCK_WIDTH-4))
		y := cast(f32)(rand.int31()%cast(i32)(BLOCK_WIDTH-4))
		wave.born = {x,y, 4,4}
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

bird_update :: proc(handle: BirdHandle, g: ^Game, delta: f64) {
	b := hla.hla_get_pointer(handle)
	if b.dest_time == 0 {
		if len(g.land) == 0 do return
		i := rand.uint32()%(auto_cast len(g.land))
		x := g.land[i].x
		y := g.land[i].y
		b.target = g.land[i]
		b.destination = {auto_cast x + rand.float32()*0.1, auto_cast y}
		b.dest_time = g.time
	}
	if b.hitpoint <= 0 {
		game_kill_bird(g, handle)
	}
	if b.dest_time != 0 {
		dir := linalg.normalize(b.destination - b.pos)
		step := b.speed*auto_cast delta
		if b.shoot_colddown > 0 {
			b.shoot_colddown -= delta
		}
		if auto_cast linalg.distance(b.destination, b.pos) < step {
			if b.shoot_colddown <= 0 {// attack
				target :Vec2i= {auto_cast b.destination.x, auto_cast b.destination.y}
				idx := get_index(target.x, target.y)
				target_building := g.buildingmap[idx]
				if target_building != nil {
					if target_building.hitpoint > 0 {
						target_building.hitpoint -= b.attack
					}
				} else {
					if g.hitpoint[idx] > 0.0 {
						g.hitpoint[idx] -= b.attack
					}
					if g.hitpoint[idx] <= 0.0 {
						g.mask[idx] = 0
						b.dest_time = 0
					}
				}
				b.shoot_colddown = b.shoot_interval
			}
		} else {
			b.pos += dir * 2 * auto_cast delta
		}
	}
}

bird_draw :: proc(bg: ^BirdGenerator) {
	rl.DrawRectangleRec(bg.wave.born, {200, 60,60, 128})
}

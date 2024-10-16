package main

import "core:fmt"
import "core:slice"
import "core:math"
import "core:math/rand"
import "core:math/noise"
import "core:math/linalg"
import rl "vendor:raylib"
import hla "collections/hollow_array"

BirdHandle :: hla.HollowArrayHandle(Bird)
Bird :: struct {
	hitpoint : int,
	pos : Vec2,

	speed : f64,
	destination : Vec2,
	dest_time : f64,
	level : int,
	attack : int,// how much damage one shoot
	shoot_interval : f64,
	shoot_colddown : f64,
	_candidates_buffer : [dynamic]_BirdTargetCandidate,

	// ai
	_building_weight_adjust : int,
}
_BirdTargetCandidate :: struct {
	is_building : bool,
	position : Vec2i,
	weight : int,
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
birdgen_is_working :: proc(bg: ^BirdGenerator) -> bool {
	return bg.wave.time > 0
}
birdgen_set :: proc(bg: ^BirdGenerator, count: int, time: f64) {
	wave : BirdWave
	if len(game.land) == 0 do return
	wave.time = auto_cast (rand.int31()%7+10)
	wave.count = auto_cast (rand.int31()%4+4)
	bx := cast(f32)(rand.int31()%cast(i32)(BLOCK_WIDTH-4))
	by := cast(f32)(rand.int31()%cast(i32)(BLOCK_WIDTH-4))
	wave.born = {bx,by, 4,4}
	ite : int
	mother : Vec2i
	for b in hla.ite_alive_value(&game.buildings, &ite) {
		if b.type == Mother {
			mother = b.position
		}
	}
	offset :Vec2i= {cast(int)rand.int31()%4, cast(int)rand.int31()%4}
	w := cast(f32)math.min(4, cast(int)BLOCK_WIDTH-(mother.x-offset.x))
	h := cast(f32)math.min(4, cast(int)BLOCK_WIDTH-(mother.y-offset.y))
	wave.target = {cast(f32)(mother.x-offset.x), cast(f32)(mother.y-offset.y), w, h}
	bg.wave = wave
}

birdgen_update :: proc(g: ^Game, bg: ^BirdGenerator, delta: f64) {
	bg.time += delta
	using bg
	if wave.time > 0 {
		wave.time -= delta
		if wave.time <= 0 {
			for i in 0..<wave.count {
				pos :Vec2= {rand.float32()*wave.born.width+wave.born.x, rand.float32()*wave.born.height+wave.born.y}
				b := game_add_bird(g, pos)
				bird := hla.hla_get_pointer(b)
				t := wave.target
				dpos := Vec2{cast(f32)(rand.int31()%cast(i32)(t.width))+t.x, cast(f32)(rand.int31()%cast(i32)(t.height))+t.y}
				if !_bird_find_target(bird, dpos) {
					bird.destination = dpos
					bird.dest_time = game.time
				}
			}
			wave.time = 0
		}
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
		if _bird_find_target(b, b.pos) do b.dest_time = g.time
		else do return
	}
	if b.hitpoint <= 0 {
		game_kill_bird(g, handle)
		return
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
	if bg.wave.time != 0 {
		rl.DrawRectangleRoundedLines(bg.wave.born, 0.6, 8, .1, {120,120,60, 128})
		rl.DrawRectangleRoundedLines(bg.wave.target, 0.6, 8, .1, {200,60,60, 128})
	}
}

@(private="file")
_bird_find_target :: proc(b: ^Bird, pos: Vec2) -> bool {
	g := &game
	if len(g.land) == 0 do return false

	clear(&b._candidates_buffer)
	for l in game.land {
		distance := linalg.distance(pos, Vec2{auto_cast l.x, auto_cast l.y});
		weight := 128 - math.min(cast(int)distance, 128)
		append(&b._candidates_buffer, _BirdTargetCandidate{ false, l, weight })
	}
	for building in hla.ites_alive_value(&game.buildings) {
		distance := linalg.distance(pos, Vec2{auto_cast building.position.x, auto_cast building.position.y})
		weight := 128 - math.min(cast(int)distance, 128)
		weight += 2 + b._building_weight_adjust
		hp_percent := cast(f64)building.hitpoint/cast(f64)building.hitpoint_define
		if hp_percent < 0.9 do weight += 1
		if hp_percent < 0.5 do weight += 1
		append(&b._candidates_buffer, _BirdTargetCandidate{ true, building.position, weight })
	}
	if len(b._candidates_buffer) == 0 do return false

	slice.sort_by_cmp(b._candidates_buffer[:], proc(a,b: _BirdTargetCandidate) -> slice.Ordering {
		if a.weight > b.weight do return .Less
		if a.weight < b.weight do return .Greater
		return .Equal
	})

	des := b._candidates_buffer[0]
	if !des.is_building do b._building_weight_adjust += 1
	else do b._building_weight_adjust = 0
	x := des.position.x
	y := des.position.y
	b.destination = {auto_cast x + rand.float32()*0.1, auto_cast y + rand.float32()*0.1}
	return true
}

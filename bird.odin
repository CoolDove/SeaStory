package main

import "core:fmt"
import "core:slice"
import "core:math"
import "core:math/rand"
import "core:math/noise"
import "core:math/linalg"
import rl "vendor:raylib"
import hla "collections/hollow_array"
import pool "collections/pool"

// Rely on game.birds to call `init` and `release`.

BirdHandle :: hla.HollowArrayHandle(Bird)

Bird :: struct {
	using __base : _BirdBase,
	__reserve : [128]u8,// dont go beyond this
}
_BirdBase :: struct {
	type : typeid,
	using vtable : ^Bird_VTable,

	hitpoint : int,
	pos : Vec2,

	level : int,

	speed : f64,
	speed_scaler : f64,
	destination : Vec2,
	dest_time : f64,
}

Bird_VTable :: struct {
	update : proc(b: ^Bird, delta: f64),
	pre_draw : proc(b: ^Bird),
	draw : proc(b: ^Bird),
	extra_draw : proc(b: ^Bird),

	init : proc(b: ^Bird), // after `new`
	release : proc(b: ^Bird), // before `free`
}

Bird_VTable_Empty :Bird_VTable= {
	update = proc(b: ^Bird, delta: f64){},
	pre_draw = proc(b: ^Bird) {},
	draw = proc(b: ^Bird) {},
	extra_draw = proc(b: ^Bird) {},

	init = proc(b: ^Bird) {},
	release = proc(b: ^Bird) {},
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


bird_init :: proc(type: typeid, bird: ^Bird) {
	bird.type = type
	bird.vtable = _bird_vtable(type)
	bird->init()
}

_bird_vtable :: proc(t: typeid) -> ^Bird_VTable {
	if t == BlackBird do return &_BlackBird_VTable
	return nil
}

bird_get_draw_elem :: proc(b: ^Bird) -> DrawElem {
	vtable := _bird_vtable(b.type)
	return DrawElem{
		b,
		auto_cast b.pos.y+0.05,
		proc(bird: rawptr) {
			bird := cast(^Bird)bird
			bird->pre_draw()
		},
		proc(bird: rawptr) {
			bird := cast(^Bird)bird
			bird->draw()
		},
		proc(bird: rawptr) {
			bird := cast(^Bird)bird
			bird->extra_draw()
		},
		proc(draw: rawptr) {
		}
	}
}

birdgen_is_working :: proc(bg: ^BirdGenerator) -> bool {
	return bg.wave.time > 0
}
birdgen_set :: proc(bg: ^BirdGenerator, count: int, time: f64) {
	wave : BirdWave
	if len(game.land) == 0 do return
	wave.time = time
	wave.count = count
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
				if !_bird_find_target(auto_cast bird, dpos) {
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

// bird_update :: proc(handle: BirdHandle, g: ^Game, delta: f64) {
// }

birdgen_draw :: proc(bg: ^BirdGenerator) {
	if bg.wave.time != 0 {
		rl.DrawRectangleRoundedLines(bg.wave.born, 0.6, 8, .1, {120,120,60, 128})
		rl.DrawRectangleRoundedLines(bg.wave.target, 0.6, 8, .1, {200,60,60, 128})
	}
}

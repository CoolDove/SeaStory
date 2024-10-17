package main

import "core:fmt"
import "core:slice"
import "core:math"
import "core:math/rand"
import "core:math/noise"
import "core:math/linalg"
import rl "vendor:raylib"
import hla "collections/hollow_array"
import "collections/pool"

BlackBird :: struct {
	using __base : _BirdBase,

	attack : int,// how much damage one shoot
	shoot_interval : f64,
	shoot_colddown : f64,

	// ai
	_building_weight_adjust : int,
}

BlackBird_VTable :_Bird_VTable(BlackBird)= {
	update = proc(using b: ^BlackBird, delta: f64){
		g := &game

		if b.dest_time == 0 {
			if _find_target(b, b.pos) do b.dest_time = g.time
			else do return
		}

		if b.dest_time != 0 {
			if b.shoot_colddown > 0 {
				b.shoot_colddown -= delta
			}
			if _bird_move_to_destination(auto_cast b, delta) {
				// arrived
				if b.shoot_colddown <= 0 {// attack
					target :Vec2i= {auto_cast b.destination.x, auto_cast b.destination.y}
					idx := get_index(target.x, target.y)
					target_building := g.buildingmap[idx]
					if target_building != nil {
						if target_building.hitpoint > 0 {
							target_building.hitpoint -= b.attack
							vfx_number(b.pos+rand.float32()*0.1, attack, ENEMY_ATK_COLOR)
						}
					} else {
						if g.hitpoint[idx] > 0.0 {
							g.hitpoint[idx] -= b.attack
							vfx_number(b.pos+rand.float32()*0.1, attack, ENEMY_ATK_COLOR)
						}
						if g.hitpoint[idx] <= 0.0 {
							b.dest_time = 0
						}
					}
					b.shoot_colddown = b.shoot_interval
				}
			}
		}
	},
	pre_draw = proc(b: ^BlackBird) {
	},
	draw = proc(b: ^BlackBird) {
		_bird_draw(auto_cast b, game.res.bird_tex)
	},
	extra_draw = proc(b: ^BlackBird) {
		_bird_extra_draw(auto_cast b)
	},

	init = proc(using b: ^BlackBird) {
		hitpoint = 100
		shoot_interval = 0.8
		attack = 6
		speed = 1.2
		speed_scaler = 1.0
	},
	prepare = proc(using b: ^BlackBird, target: rl.Rectangle) {
		t := target
		dpos := Vec2{cast(f32)(rand.int31()%cast(i32)(t.width))+t.x, cast(f32)(rand.int31()%cast(i32)(t.height))+t.y}
		if !_find_target(auto_cast b, dpos) {
			b.destination = dpos
			b.dest_time = game.time
		}
	},
	release = proc(using b: ^BlackBird) {
	},
}

@(private="file")
_find_target :: proc(b: ^BlackBird, pos: Vec2) -> bool {
	g := &game
	if len(g.land) == 0 do return false

	buffer_pool := &game.birds_ai_buffer_pool
	candidates_buffer := pool.get(buffer_pool)
	defer pool.retire(buffer_pool, candidates_buffer)
	clear(&candidates_buffer)
	for l in game.land {
		distance := linalg.distance(pos, Vec2{auto_cast l.x, auto_cast l.y});
		weight := 128 - math.min(cast(int)distance, 128)
		append(&candidates_buffer, _BirdTargetCandidate{ false, l, weight })
	}
	for building in hla.ites_alive_value(&game.buildings) {
		distance := linalg.distance(pos, Vec2{auto_cast building.position.x, auto_cast building.position.y})
		weight := 128 - math.min(cast(int)distance, 128)
		weight += 2 + b._building_weight_adjust

		if building.type == Wind do weight = math.max(0, weight-10)

		hp_percent := cast(f64)building.hitpoint/cast(f64)building.hitpoint_define
		if hp_percent < 0.9 do weight += 1
		if hp_percent < 0.5 do weight += 1
		append(&candidates_buffer, _BirdTargetCandidate{ true, building.position, weight })
	}
	if len(candidates_buffer) == 0 do return false

	_bird_sort_candidates(candidates_buffer[:])

	des := candidates_buffer[0]

	if !des.is_building do b._building_weight_adjust += 2
	else do b._building_weight_adjust = 0
	x := des.position.x
	y := des.position.y
	b.destination = {auto_cast x + rand.float32()*0.3, auto_cast y + rand.float32()*0.3}
	return true
}

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
	_candidates_buffer : [dynamic]_BirdTargetCandidate,

	// ai
	_building_weight_adjust : int,
}

_BlackBird_VTable :Bird_VTable= {
	update = proc(b: ^Bird, delta: f64){
		b := cast(^BlackBird)b
		g := &game

		if b.dest_time == 0 {
			if _bird_find_target(b, b.pos) do b.dest_time = g.time
			else do return
		}

		if b.speed_scaler < 1.0 {
			b.speed_scaler += math.min(1, 1 * delta)
		}
		if b.dest_time != 0 {
			dir := linalg.normalize(b.destination - b.pos)
			step := b.speed*b.speed_scaler*auto_cast delta
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
				b.pos += dir * auto_cast step
			}
		}
	},
	pre_draw = proc(b: ^Bird) {
	},
	draw = proc(b: ^Bird) {
		x,y := b.pos.x, b.pos.y
		rl.DrawTexturePro(game.res.bird_tex, {0,0,32,32}, {x+0.2,y+0.2, 1,1}, {0,0}, 0, {0,0,64,64})// shadow
		rl.DrawTexturePro(game.res.bird_tex, {0,0,32,32}, {x,y, 1,1}, {0,0}, 0, rl.WHITE)
	},
	extra_draw = proc(b: ^Bird) {
		bird := cast(^BlackBird)b
		if GAME_DEBUG {
			rl.DrawLineV(bird.pos, bird.destination, {255,0,0, 64})
		}
	},

	init = proc(b: ^Bird) {
		b := cast(^BlackBird)b
		using b
		hitpoint = 100
		shoot_interval = 0.8
		attack = 6
		speed = 1.2
		speed_scaler = 1.0
		fmt.printf("black bird init\n")
	},
	release = proc(b: ^Bird) {
		b := cast(^BlackBird)b
		using b
	},
}

_bird_find_target :: proc(b: ^BlackBird, pos: Vec2) -> bool {
	g := &game
	if len(g.land) == 0 do return false

	buffer_pool := &game.birds_ai_buffer_pool
	b._candidates_buffer = pool.get(buffer_pool)
	defer pool.retire(buffer_pool, b._candidates_buffer)
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

		if building.type == Wind do weight = math.max(0, weight-10)

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
	fmt.printf("find target, candidates count: {}\n", len(b._candidates_buffer))
	if !des.is_building do b._building_weight_adjust += 2
	else do b._building_weight_adjust = 0
	x := des.position.x
	y := des.position.y
	b.destination = {auto_cast x + rand.float32()*0.1, auto_cast y + rand.float32()*0.1}
	return true
}

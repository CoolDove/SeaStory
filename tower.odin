package main

import "core:math/rand"
import "core:math/noise"
import "core:math/linalg"
import "core:math"
import rl "vendor:raylib"
import hla "collections/hollow_array"

Tower :: struct {
	pos : Position,
	level : int,
	target : hla.HollowArrayHandle(Bird),
	range : f64,

	shoot_interval : f64,
	shoot_charge : f64,
}

tower_update :: proc(tower: ^Tower, g: ^Game, delta: f64) {
	using hla

	if tower.shoot_charge < tower.shoot_interval {
		tower.shoot_charge += delta
	}

	tower_center :rl.Vector2= {cast(f32)tower.pos.x + 0.5, cast(f32)tower.pos.y + 0.5}
	
	if b, ok := hla.hla_get_pointer(tower.target); ok {
		if linalg.distance(b.pos, tower_center) > auto_cast tower.range {// 超出范围，丢失锁定
			tower.target = {}
		} else if tower.shoot_charge >= tower.shoot_interval {
			// game_kill_bird(g, tower.target)
			bird := hla.hla_get_pointer(tower.target)
			bird.hitpoint -= 25
			tower.shoot_charge = 0
		}
	} else {
		distance :f32= auto_cast tower.range
		for candi in hla.ites_alive_handle(&g.birds) {
			d := linalg.distance(hla.hla_get_pointer(candi).pos, tower_center)
			if d < auto_cast distance {
				distance = d
				tower.target = candi
				tower.shoot_charge = 0
			}
		}
	}
}

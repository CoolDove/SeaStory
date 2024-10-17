package main

import "core:math/rand"
import "core:math/noise"
import "core:math/linalg"
import "core:math"
import "core:fmt"
import rl "vendor:raylib"
import hla "collections/hollow_array"

FogTower :: struct {
	using _ : Building,
	// define
	shoot_interval : f64,

	// run
	shoot_charge : f64,
}

_FogTower_VTable :Building_VTable(FogTower)= {
	update = proc(using ftower: ^FogTower, delta: f64) {
		if powered > 0 {
			if shoot_charge < shoot_interval {
				shoot_charge += delta
				if shoot_charge >= shoot_interval {
					shoot_charge = shoot_interval
				}
			} else {
				ite:int
				shot := false
				for bird in hla.ite_alive_ptr(&game.birds, &ite) {
					if linalg.distance(bird.pos, center) < auto_cast range {
						dmg := math.min(6, bird.hitpoint)
						bird.hitpoint -= dmg
						vfx_number(bird.pos+rand.float32()*0.1, dmg, PLAYER_ATK_COLOR)
						shot = true
					}
				}
				if shot {
					shoot_charge = 0
					vfx_impact(center, auto_cast range, 0.8)
					ite:Vec3i
					for p in ite_around(position, cast(int)range*2, &ite) {
						idx := get_index(p)
						if in_range(p) && game.block[idx] == ITEM_QUESTION && 
							linalg.distance(get_center(p), center) < cast(f32)range 
						{
							game.block[idx] = count_around(p)
							vfx_boom(get_center(p), 0.5, 0.6)
						}
					}
				}
			}
		}
	},
	pre_draw = proc(ftower: ^FogTower) {
		if GAME_DEBUG {
			rl.DrawCircleLinesV(ftower.center, auto_cast ftower.range, {255, 100, 100, 128})
		}
		if game.hover_cell == ftower.position || rl.IsKeyDown(.LEFT_SHIFT) {
			rl.DrawCircleV(ftower.center, auto_cast ftower.range, {200, 100, 80, cast(u8)(64.0*math.abs(math.sin(game.time))+64.0)})
			rl.DrawCircleLinesV(ftower.center, auto_cast ftower.range, {255, 100, 100, 128})
		}
	},
	draw = proc(using ftower: ^FogTower) {
		tex := game.res.fog_tower_tex
		height := cast(f32) tex.height
		x, y :f32= cast(f32)position.x,cast(f32)position.y
		rl.DrawTexturePro(tex, {1,0,32, height}, {x,y, 1, height/32.0}, {0,1}, 0, rl.WHITE)
	},
	extra_draw = proc(using ftower: ^FogTower) {
		draw_building_hpbar(ftower)
		if powered <= 0 {
			draw_building_nopower(ftower)
		}
		if GAME_DEBUG && game.hover_cell == position {
			ite:Vec3i
			for p in ite_around(position, cast(int)range+1, &ite) {
				idx := get_index(p)
				rl.DrawCircleV(get_center(p), 0.2, {0,0,255, 32})
				if in_range(p) &&// game.block[idx] == ITEM_QUESTION && 
					linalg.distance(get_center(p), center) < cast(f32)range 
				{
					rl.DrawCircleV(get_center(p), 0.3, {255,0,0, 32})
					if game.block[idx] == ITEM_QUESTION {
						rl.DrawCircleV(get_center(p), 0.35, {255,255,0, 32})
					}
				}
			}
		}
	},
	preview_draw = proc(pos: Vec2i) {
		rl.DrawCircleLinesV(get_center(pos), 4, {255, 100, 100, 128})
	},

	init = proc(using ftower: ^FogTower) {
		shoot_interval = 1.5
		range = 4
	},
	release = proc(ftower: ^FogTower) {},

	_is_place_on_water = proc() -> bool { return false },
	_define_hitpoint = proc() -> int { return 200 }
}

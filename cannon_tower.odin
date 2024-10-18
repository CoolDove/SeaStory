package main

import "core:math/rand"
import "core:math/noise"
import "core:math/linalg"
import "core:math"
import "core:fmt"
import rl "vendor:raylib"
import hla "collections/hollow_array"
import tw "tween"

CannonTower :: struct {
	using _ : Building,
	// define
	shoot_interval : f64,

	// run
	shoot_charge : f64,
	shoot_target : Vec2,
	shooting : f64,
}

@(private="file")
_range :f32= 5

_CannonTower_VTable :Building_VTable(CannonTower)= {
	update = proc(using ctower: ^CannonTower, delta: f64) {
		if powered > 0 {
			if shooting > 0 {
				shooting -= delta
				if shooting <= 0 {
					ite:int
					for bird in hla.ite_alive_ptr(&game.birds, &ite) {
						bpos := bird.pos+{0.5,0.5}
						if linalg.distance(bpos, shoot_target) < 0.4 {
							dmg := math.min(bird.hitpoint, 10)
							bird.hitpoint -= dmg
							vfx_number(bpos, dmg, PLAYER_ATK_COLOR)
						}
					}
					vfx_boom(shoot_target, 0.4, 0.5)
					shooting = 0
				}
			} else if shoot_charge < shoot_interval {
				shoot_charge += delta
				if shoot_charge >= shoot_interval {
					shoot_charge = shoot_interval
				}
			} else {
				ite:int
				shot := false
				available := make([dynamic]^Bird); defer delete(available)
				for bird in hla.ite_alive_ptr(&game.birds, &ite) {
					if linalg.distance(bird.pos, center) < auto_cast range {
						append(&available, bird)
					}
				}
				if len(available) > 0 {
					idx := rand.int31()%auto_cast len(available)
					target := available[idx]
					shoot_target = target.pos+{0.5,0.5}
					shooting = 0.2

					VfxBullet :: struct {
						using __base : _VfxBase,
						from, to : Vec2,
					}
					vfxh := hla.hla_append(&game.vfx, Vfx{})
					vfx := hla.hla_get_pointer(vfxh)
					vfx^ = vfx_create(shooting,
						eextra_draw(vfx, auto_cast proc(vfx: ^VfxBullet) {
							using vfx
							t := cast(f32)(vfx.life/vfx.duration)
							pos := t * (to-from) + from
							rl.DrawCircleV(pos, 0.05, {240,230,128, 255})
						})
					)
					bullet := cast(^VfxBullet)vfx
					bullet.from = center + {0, -0.6}
					bullet.to = shoot_target
					shoot_charge = 0
				}
			}
		}
	},
	pre_draw = proc(ctower: ^CannonTower) {
		if GAME_DEBUG {
			rl.DrawCircleLinesV(ctower.center, auto_cast ctower.range, {255, 100, 100, 128})
		}
		if game.hover_cell == ctower.position || rl.IsKeyDown(.LEFT_SHIFT) {
			rl.DrawCircleV(ctower.center, auto_cast ctower.range, {200, 100, 80, cast(u8)(64.0*math.abs(math.sin(game.time))+64.0)})
			rl.DrawCircleLinesV(ctower.center, auto_cast ctower.range, {255, 100, 100, 128})
		}
	},
	draw = proc(using ctower: ^CannonTower) {
		tex := game.res.cannon_tower_tex
		height := cast(f32) tex.height
		x, y :f32= cast(f32)position.x,cast(f32)position.y
		rl.DrawTexturePro(tex, {1,0,32, height}, {x,y, 1, height/32.0}, {0,1}, 0, rl.WHITE)
	},
	extra_draw = proc(using ctower: ^CannonTower) {
		draw_building_hpbar(ctower)
		if powered <= 0 {
			draw_building_nopower(ctower)
		}
	},
	preview_draw = proc(pos: Vec2i) {
		rl.DrawCircleV(get_center(pos), _range, {100, 255, 100, 128})
	},

	init = proc(using ctower: ^CannonTower) {
		shoot_interval = 1.5
		range = auto_cast _range
	},
	release = proc(ctower: ^CannonTower) {},

	_is_place_on_water = proc() -> bool { return false },
	_define_hitpoint = proc() -> int { return 300 }
}

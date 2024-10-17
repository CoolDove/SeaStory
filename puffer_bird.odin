package main

import "core:fmt"
import "core:slice"
import "core:math"
import "core:hash"
import "core:math/rand"
import "core:math/noise"
import "core:math/linalg"
import rl "vendor:raylib"
import hla "collections/hollow_array"
import "collections/pool"
import tw "tween"

PufferBird :: struct {
	using __base : _BirdBase,

	attack : int, // how much damage the explosion deals
	range : f64, // the range of the explosion
	boomed : bool,
}

PufferBird_VTable :_Bird_VTable(PufferBird)= {
	update = proc(b: ^PufferBird, delta: f64) {
		if b.boomed {
			b.hitpoint = 0
			return
		}
		if b.dest_time == 0 {
			if _find_target(b, {}) do b.dest_time = game.time
		} else {
			if _bird_move_to_destination(auto_cast b, delta, 0.3) {
				using b
				boomed = true
				ite:int
				for building in hla.ite_alive_value(&game.buildings, &ite) {
					if linalg.distance(building.center, pos) < 2 {
						building.hitpoint -= attack
						vfx_number(b.pos, attack, ENEMY_ATK_COLOR)

						VfxBoom :: struct {
							using __base : _VfxBase,
							center : Vec2,
							range : f32,
							life : f32,
						}
						vfxh := hla.hla_append(&game.vfx, Vfx{})
						vfx := hla.hla_get_pointer(vfxh)
						vfx^ = vfx_create(
							proc(v: ^Vfx, delta: f64) {
								v := cast(^VfxBoom)v
								if v.life <= 0 do v.die = true
							},
							eextra_draw(vfx, auto_cast proc(vfx: ^VfxBoom) {
								alpha :u8= cast(u8)(255.0 * vfx.life)
								rl.DrawCircleV(vfx.center, vfx.range+vfx.range*0.5*(1-vfx.life), {128,128,128, alpha/2})
								rl.DrawCircleV(vfx.center, vfx.range, {255,255,255, alpha})
							})
						)
						boom := cast(^VfxBoom)vfx
						boom.life = 1.0
						boom.center = b.pos+{0.5,0.5}
						boom.range = auto_cast b.range
						tw.tween(&game.tweener, &boom.life, 0, 0.6, tw.ease_outcirc)
					}
				}
			}
		}
	},
	pre_draw = proc(b: ^PufferBird) {},
	draw = proc(b: ^PufferBird) {
		_bird_draw(auto_cast b, game.res.puffer_tex)
	},
	extra_draw = proc(b: ^PufferBird) {
		_bird_extra_draw(auto_cast b)
		if b.boomed do rl.DrawCircleV(b.pos+{0.5,0.5}, cast(f32)b.range, rl.WHITE)
	},

	init = proc(using b: ^PufferBird) {
		hitpoint = 200
		attack = 140
		speed = 0.8
		speed_scaler = 1.0

		b.range = 0.7
	},
	prepare = proc(b: ^PufferBird, target: rl.Rectangle) {
		if _find_target(b, target) {
			b.dest_time = game.time
		}
	},
	release = proc(b: ^PufferBird) {},
}

@(private="file")
_find_target :: proc(b: ^PufferBird, target: rl.Rectangle) -> bool {
	ite : int
	center :Vec2= {target.x, target.y} + 0.5 * {target.width, target.height}

	if game.buildings.count == 0 do return false

	buffer_pool := &game.birds_ai_buffer_pool
	candidates_buffer := pool.get(buffer_pool)
	defer pool.retire(buffer_pool, candidates_buffer)
	clear(&candidates_buffer)

	for building in hla.ite_alive_value(&game.buildings, &ite) {
		distance := linalg.distance(b.pos, building.center)
		weight := 128 - math.min(cast(int)distance, 128)
		append(&candidates_buffer, _BirdTargetCandidate{ true, building.position, weight })
	}

	_bird_sort_candidates(candidates_buffer[:])

	des := candidates_buffer[0]
	x, y := des.position.x, des.position.y
	b.destination = {auto_cast x + rand.float32()*0.1, auto_cast y + rand.float32()*0.1}

	return true
}

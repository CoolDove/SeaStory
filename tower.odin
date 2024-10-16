package main

import "core:math/rand"
import "core:math/noise"
import "core:math/linalg"
import "core:math"
import "core:fmt"
import rl "vendor:raylib"
import hla "collections/hollow_array"

Tower :: struct {
	using _ : Building,
	// define
	range : f64,
	shoot_interval : f64,

	// run
	shoot_charge : f64,
	target : BirdHandle,
}

_Tower_VTable :Building_VTable= {
	update = proc(handle: hla._HollowArrayHandle, delta: f64) {
		using hla
		tower := hla_get_value(transmute(hla.HollowArrayHandle(^Tower))handle)

		if tower.shoot_charge < tower.shoot_interval && tower.powered > 0 {
			tower.shoot_charge += delta
		}

		tower_center :rl.Vector2= {cast(f32)tower.position.x + 0.5, cast(f32)tower.position.y + 0.5}
		
		if b, ok := hla.hla_get_pointer(tower.target); ok {
			if linalg.distance(b.pos, tower_center) > auto_cast tower.range {// 超出范围，丢失锁定
				tower.target = {}
			} else if tower.shoot_charge >= tower.shoot_interval {
				bird := hla.hla_get_pointer(tower.target)
				bird.hitpoint -= 20
				tower.shoot_charge = 0
			}
		} else {
			distance :f32= auto_cast tower.range
			for candi in hla.ites_alive_handle(&game.birds) {
				d := linalg.distance(hla.hla_get_pointer(candi).pos, tower_center)
				if d < auto_cast distance {
					distance = d
					tower.target = candi
					tower.shoot_charge = 0
				}
			}
		}
	},
	pre_draw = proc(handle: hla._HollowArrayHandle) {
		using hla
		tower := hla_get_value(transmute(hla.HollowArrayHandle(^Tower))handle)
		if GAME_DEBUG {
			rl.DrawCircleLinesV(tower.center, auto_cast tower.range, {255, 100, 100, 128})
		}
		if game.hover_cell == tower.position || rl.IsKeyDown(.LEFT_SHIFT) {
			rl.DrawCircleV(tower.center, auto_cast tower.range, {200, 100, 80, cast(u8)(64.0*math.abs(math.sin(game.time))+64.0)})
			rl.DrawCircleLinesV(tower.center, auto_cast tower.range, {255, 100, 100, 128})
		}
	},
	draw = proc(handle: hla._HollowArrayHandle) {
		using hla
		tower := hla_get_value(transmute(hla.HollowArrayHandle(^Tower))handle)
		tex := game.res.tower_tex
		height := cast(f32) tex.height
		rl.DrawTexturePro(tex, {0,0,32, height}, {cast(f32)tower.position.x,cast(f32)tower.position.y, 1, height/32.0}, {0,1}, 0, rl.WHITE)
	},
	extra_draw = proc(handle: hla._HollowArrayHandle) {
		using hla
		tower := hla_get_value(transmute(hla.HollowArrayHandle(^Tower))handle)
		draw_building_hpbar(tower)
		if tower.powered > 0 {
			from := tower.center - {0,1.0}
			if target, ok := hla.hla_get_pointer(tower.target); ok {
				thickness :f32= auto_cast (0.3*tower.shoot_charge/tower.shoot_interval)
				rl.DrawLineEx(from, target.pos+{0.5,0.5}, thickness, {80, 100, 160, 128})
				rl.DrawLineEx(from, target.pos+{0.5,0.5}, thickness*0.4, {200, 230, 220, 255})
			}
		} else {
			draw_building_nopower(tower)
		}
		if GAME_DEBUG {
			rl.DrawTextEx(FONT_DEFAULT, fmt.ctprintf("power: {}", tower.powered), tower.center+{-0.5, 0.4}, 0.4, 0, {0,0,0, 128})
		}
	},
	init = proc(b: ^Building) {
		t := cast(^Tower)b
		t.range = 4 
		t.shoot_interval = 0.25
	}, 
	release = proc(b: ^Building) {},
	_is_place_on_water = Building_VTable_Empty._is_place_on_water,
	_define_hitpoint = proc() -> int { return 350 }
}

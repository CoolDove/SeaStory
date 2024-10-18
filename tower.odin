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
	shoot_interval : f64,

	// run
	shoot_charge : f64,
	target : BirdHandle,

	attack : int,

	heat : f64,
	heat_max : f64,
	heat_max_scaler : f64,
}

@(private="file")
_range :f32= 3

_Tower_VTable :Building_VTable(Tower)= {
	update = proc(tower: ^Tower, delta: f64) {
		if tower.shoot_charge < tower.shoot_interval && tower.powered > 0 {
			tower.shoot_charge += delta
		}
		tower_center :rl.Vector2= {cast(f32)tower.position.x + 0.5, cast(f32)tower.position.y + 0.5}

		tower.heat = math.max(0, tower.heat-2*delta)
		
		if b, ok := hla.hla_get_pointer(tower.target); ok {
			if linalg.distance(b.pos, tower_center) > auto_cast tower.range {// 超出范围，丢失锁定
				tower.target = {}
			} else if tower.shoot_charge >= tower.shoot_interval {
				bird := hla.hla_get_pointer(tower.target)
				using tower
				dmg := tower.attack + cast(int)(cast(f64)tower.attack * (heat_max_scaler * (heat/heat_max)))
				dmg = math.min(bird.hitpoint, dmg)
				bird.hitpoint -= dmg
				tower.shoot_charge = 0
				vfx_number(bird.pos+rand.float32()*0.1, dmg, PLAYER_ATK_COLOR)
				tower.heat = math.min(tower.heat + 3*tower.shoot_interval, tower.heat_max)
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
	pre_draw = proc(tower: ^Tower) {
		if GAME_DEBUG {
			rl.DrawCircleLinesV(tower.center, auto_cast tower.range, {255, 100, 100, 128})
		}
		if game.hover_cell == tower.position || rl.IsKeyDown(.LEFT_SHIFT) {
			rl.DrawCircleV(tower.center, auto_cast tower.range, {200, 100, 80, cast(u8)(64.0*math.abs(math.sin(game.time))+64.0)})
			rl.DrawCircleLinesV(tower.center, auto_cast tower.range, {255, 100, 100, 128})
		}
	},
	preview_draw = proc(pos: Vec2i) {
		rl.DrawCircleV(get_center(pos), _range, {100, 255, 100, 128})
	},
	draw = proc(tower: ^Tower) {
		tex := game.res.tower_tex
		height := cast(f32) tex.height
		rl.DrawTexturePro(tex, {0,0,32, height}, {cast(f32)tower.position.x,cast(f32)tower.position.y, 1, height/32.0}, {0,1}, 0, rl.WHITE)
	},
	extra_draw = proc(using tower: ^Tower) {
		{// heat bar
			heat_rect :rl.Rectangle= {center.x-0.3, center.y+0.05, 0.6, 0.1}
			rl.DrawRectangleRec({heat_rect.x-0.03, heat_rect.y-0.03, heat_rect.width+0.06, heat_rect.height+0.06}, rl.BLACK)
			rl.DrawRectangleRec(heat_rect, rl.BLACK)
			fill := heat_rect
			fill.width *= cast(f32)(heat/heat_max)
			rl.DrawRectangleRec(fill, rl.ORANGE)
		}

		draw_building_hpbar(tower)
		if tower.powered > 0 {
			from := tower.center - {0, 1.2}
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
	init = proc(using tower: ^Tower) {
		range = auto_cast _range 
		shoot_interval = 0.25
		attack = 8
		heat_max = 10
		heat_max_scaler = 1.5
	}, 
	release = proc(tower: ^Tower) {},

	_is_place_on_water = Building_VTable_Empty._is_place_on_water,
	_define_hitpoint = proc() -> int { return 350 }
}

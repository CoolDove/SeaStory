package main

import "core:math/rand"
import "core:math/noise"
import "core:math/linalg"
import "core:math"
import rl "vendor:raylib"
import hla "collections/hollow_array"


PowerPump :: struct {
	using _ : Building,
	range : f64,
}

@private
_PowerPump_VTable :Building_VTable= {
	update = proc(handle: hla._HollowArrayHandle, delta: f64) {
		using hla
		power_pump := hla_get_value(transmute(hla.HollowArrayHandle(^PowerPump))handle)
		if !building_need_bomb_check(power_pump) do return
	},
	draw = proc(handle: hla._HollowArrayHandle) {
		using hla
		power_pump := hla_get_value(transmute(hla.HollowArrayHandle(^PowerPump))handle)
		tex := game.res.power_pump_tex
		height := cast(f32) tex.height
		if GAME_DEBUG {
			rl.DrawCircleLinesV(power_pump.center, auto_cast power_pump.range, {100, 200, 100, 200})
		}
		if game.hover_cell == power_pump.position || rl.IsKeyDown(.LEFT_ALT) {
			rl.DrawCircleV(power_pump.center, auto_cast power_pump.range, {40, 200, 50, cast(u8)(32.0*math.abs(math.sin(game.time))+16.0)})
			rl.DrawCircleLinesV(power_pump.center, auto_cast power_pump.range, {100, 200, 100, 200})
			ite : int
			for b in hla.ite_alive_value(&game.buildings, &ite) {
				if b.powered < 0 || b.position == power_pump.position do continue
				if linalg.distance(b.center, power_pump.center) < auto_cast power_pump.range {
					rl.DrawLineEx(b.center, power_pump.center, auto_cast(0.1 * math.abs(math.sin(game.time*4+4.2)) + 0.2), {80, 180, 160, 128})
					rl.DrawLineEx(b.center, power_pump.center, auto_cast(0.1 * math.abs(math.sin(game.time*4)) + 0.05), {120, 220, 190, 200})
				}
			}
		}
		rl.DrawTexturePro(tex, {0,0,32, height}, {cast(f32)power_pump.position.x,cast(f32)power_pump.position.y, 1, height/32.0}, {0,0}, 0, rl.WHITE)
	},
	extra_draw = proc(handle: hla._HollowArrayHandle) {
		using hla
		power_pump := hla_get_value(transmute(hla.HollowArrayHandle(^PowerPump))handle)
		draw_building_hpbar(power_pump)
	},
	init = proc(b: ^Building) {
		power_pump := cast(^PowerPump)b
		power_pump.range = 6
		ite : int
		for b in hla.ite_alive_value(&game.buildings, &ite) {
			if b.powered < 0 || b.position == power_pump.position do continue
			if linalg.distance(b.center, power_pump.center) < auto_cast power_pump.range {
				b.powered += 1
			}
		}
	},
	release = proc(b: ^Building) {
		power_pump := cast(^PowerPump)b
		ite : int
		for b in hla.ite_alive_value(&game.buildings, &ite) {
			if linalg.distance(b.center, power_pump.center) < auto_cast power_pump.range {
				if b.powered != -1 do b.powered -= 1
			}
		}
	},
	_is_place_on_water = proc() -> bool {
		return true
	},
	_define_hitpoint = proc() -> int { return 100 }
}

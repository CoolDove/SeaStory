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

power_pump_new :: proc(position: Vec2i) -> ^PowerPump {
	t :^PowerPump= new(PowerPump)
	t._vtable = &_PowerPump_VTable
	t.type = PowerPump
	t.position = position
	t.hitpoint = 150
	t.hitpoint_define = 150
	t.center = Vec2{cast(f32)position.x, cast(f32)position.y} + {0.5, 0.5}
	t.range = 6
	return t
}

power_pump_free :: proc(ptr: ^PowerPump) {
	free(ptr)
}

@(private="file")
_power_pump_update :: proc(handle: hla._HollowArrayHandle, delta: f64) {
	using hla
	power_pump := hla_get_value(transmute(hla.HollowArrayHandle(^PowerPump))handle)
}
@(private="file")
_power_pump_draw :: proc(handle: hla._HollowArrayHandle) {
	using hla
	power_pump := hla_get_value(transmute(hla.HollowArrayHandle(^PowerPump))handle)
	tex := game.res.power_pump_tex
	height := cast(f32) tex.height
	rl.DrawCircleLinesV(power_pump.center, auto_cast power_pump.range, {100, 200, 100, 200})
	rl.DrawTexturePro(tex, {0,0,32, height}, {cast(f32)power_pump.position.x,cast(f32)power_pump.position.y, 1, height/32.0}, {0,0}, 0, rl.WHITE)
}
@(private="file")
_power_pump_extra_draw :: proc(handle: hla._HollowArrayHandle) {
	using hla
	power_pump := hla_get_value(transmute(hla.HollowArrayHandle(^PowerPump))handle)
	center := power_pump.center
	draw_building_hpbar(power_pump);
}

@private
_PowerPump_VTable :Building_VTable= {
	update = _power_pump_update,
	draw = _power_pump_draw,
	extra_draw = _power_pump_extra_draw,

	init = proc(b: ^Building) {
		power_pump := cast(^PowerPump)b
		ite : int
		for b in hla.ite_alive_value(&game.buildings, &ite) {
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
}

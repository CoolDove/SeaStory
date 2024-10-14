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
	t.position = position
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
	rl.DrawTexturePro(tex, {0,0,32, height}, {cast(f32)power_pump.position.x,cast(f32)power_pump.position.y, 1, height/32.0}, {0,0}, 0, rl.WHITE)
}
@(private="file")
_power_pump_extra_draw :: proc(handle: hla._HollowArrayHandle) {
	using hla
	power_pump := hla_get_value(transmute(hla.HollowArrayHandle(^PowerPump))handle)
}

@private
_PowerPump_VTable :Building_VTable= {
	update = _power_pump_update,
	draw = _power_pump_draw,
	extra_draw = _power_pump_extra_draw,
}

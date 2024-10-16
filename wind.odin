package main

import "base:runtime"
import "core:fmt"
import "core:strconv"
import "core:slice"
import "core:math/rand"
import "core:math/noise"
import "core:math/linalg"
import "core:math"
import "core:strings"
import hla "collections/hollow_array"
import rl "vendor:raylib"

Wind :: struct {
	using _ : Building,
}

@private
_Wind_VTable :Building_VTable= {
	update = proc(handle: hla._HollowArrayHandle, delta: f64) {
		using hla
		wind := hla_get_value(transmute(hla.HollowArrayHandle(^Wind))handle)
		using wind
		ite : int
		if powered>0 {
			for b in hla.ite_alive_ptr(&game.birds, &ite) {
				if linalg.distance(b.pos, wind.center) < 0.8 {
					b.speed_scaler = 0.3
				}
			}
		}
	},
	init = proc(b: ^Building) {
		wind := cast(^Wind)b
	},
	release = proc(b: ^Building) {
		wind := cast(^Wind)b
	},
	draw = proc(handle: hla._HollowArrayHandle) {
		using hla
		wind := hla_get_value(transmute(hla.HollowArrayHandle(^Wind))handle)
		tex := game.res.wind_off_tex
		height := cast(f32) tex.height
		rl.DrawTexturePro(tex, {0,0,32, height}, {cast(f32)wind.position.x,cast(f32)wind.position.y, 1, height/32.0}, {0,0}, 0, rl.WHITE)
	},
	extra_draw = proc(handle: hla._HollowArrayHandle) {
		using hla
		wind := hla_get_value(transmute(hla.HollowArrayHandle(^Wind))handle)
		draw_building_hpbar(wind)
		if wind.powered <= 0 {
			draw_building_nopower(wind)
		}
	},
	_is_place_on_water = proc() -> bool {
		return false
	},
	_define_hitpoint = proc() -> int { return 80 }
}

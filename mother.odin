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

Mother :: struct {
	using _ : Building,
}

@private
_Mother_VTable :Building_VTable= {
	update = proc(handle: hla._HollowArrayHandle, delta: f64) {
	},
	init = proc(b: ^Building) {
	},
	release = Building_VTable_Empty.release,
	draw = proc(handle: hla._HollowArrayHandle) {
		using hla
		mother := hla_get_value(transmute(hla.HollowArrayHandle(^Mother))handle)
		tex := game.res.mother_tex
		height := cast(f32) tex.height
		rl.DrawTexturePro(tex, {0,0,32, height}, {cast(f32)mother.position.x,cast(f32)mother.position.y, 1, height/32.0}, {0,0}, 0, rl.WHITE)
	},
	extra_draw = proc(handle: hla._HollowArrayHandle) {
		using hla
		station := hla_get_value(transmute(hla.HollowArrayHandle(^Minestation))handle)
		draw_building_hpbar(station)
	},
	_is_place_on_water = proc() -> bool {
		return false
	},
	_define_hitpoint = proc() -> int { return 600 }
}

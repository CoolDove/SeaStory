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

Probe :: struct {
	using _ : Building,
	auto_die : f64,
}

@private
_Probe_VTable :Building_VTable= {
	update = proc(handle: hla._HollowArrayHandle, delta: f64) {
		using hla
		pb := hla_get_value(transmute(hla.HollowArrayHandle(^Probe))handle)
		if !building_need_bomb_check(pb) do return
		idx := get_index(pb.position)
		if game.block[idx] == ITEM_BOMB {
			pb.auto_die -= delta
			if pb.auto_die <= 0 {
				pb.hitpoint = 0
				game.mask[idx] = FLAG_MARKED
			}
		}
	},
	init = proc(b: ^Building) {
		pb := cast(^Probe)b
		pb.powered = -1
		pb.auto_die = 0.6
	},
	release = proc(b: ^Building) {
		pb := cast(^Probe)b
	},
	draw = proc(handle: hla._HollowArrayHandle) {
		using hla
		pb := hla_get_value(transmute(hla.HollowArrayHandle(^Probe))handle)
		tex := game.res.probe_tex
		height := cast(f32) tex.height
		rl.DrawTexturePro(tex, {0,0,32, height}, {cast(f32)pb.position.x,cast(f32)pb.position.y, 1, height/32.0}, {0,0}, 0, rl.WHITE)
	},
	extra_draw = proc(handle: hla._HollowArrayHandle) {
		using hla
		pb := hla_get_value(transmute(hla.HollowArrayHandle(^Probe))handle)
		draw_building_hpbar(pb)
	},
	_is_place_on_water = proc() -> bool {
		return true
	},
	_define_hitpoint = proc() -> int { return 50 }
}

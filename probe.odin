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
_Probe_VTable :Building_VTable(Probe)= {
	update = proc(pb: ^Probe, delta: f64) {
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
	init = proc(pb: ^Probe) {
		pb.powered = -1
		pb.auto_die = 0.6
	},
	release = proc(pb: ^Probe) {
	},
	pre_draw = auto_cast Building_VTable_Empty.pre_draw,
	draw = proc(pb: ^Probe) {
		tex := game.res.probe_tex
		height := cast(f32) tex.height
		rl.DrawTexturePro(tex, {0,0,32, height}, {cast(f32)pb.position.x,cast(f32)pb.position.y, 1, height/32.0}, {0,0}, 0, rl.WHITE)
	},
	extra_draw = proc(pb: ^Probe) {
		draw_building_hpbar(pb)
	},
	_is_place_on_water = proc() -> bool {
		return true
	},
	_define_hitpoint = proc() -> int { return 50 }
}

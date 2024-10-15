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

Minestation :: struct {
	using _ : Building,
	collect_interval : f64,
	collect_time : f64,
	collect_amount : int,
}

@private
_Minestation_VTable :Building_VTable= {
	update = proc(handle: hla._HollowArrayHandle, delta: f64) {
		using hla
		station := hla_get_value(transmute(hla.HollowArrayHandle(^Minestation))handle)
		using station
		if !building_need_bomb_check(station) do return
		
		if station.powered > 0 {
			collect_time += delta
			if collect_time >= collect_interval {
				game.mineral += collect_amount
				collect_time = 0
			}
		}
	},
	init = proc(b: ^Building) {
		station := cast(^Minestation)b
		station.collect_interval = 1
		station.collect_amount = 5
	},
	release = Building_VTable_Empty.release,
	draw = proc(handle: hla._HollowArrayHandle) {
		using hla
		station := hla_get_value(transmute(hla.HollowArrayHandle(^Minestation))handle)
		tex := game.res.minestation_tex
		height := cast(f32) tex.height
		rl.DrawTexturePro(tex, {0,0,32, height}, {cast(f32)station.position.x,cast(f32)station.position.y, 1, height/32.0}, {0,0}, 0, rl.WHITE)
	},
	extra_draw = proc(handle: hla._HollowArrayHandle) {
		using hla
		station := hla_get_value(transmute(hla.HollowArrayHandle(^Minestation))handle)
		draw_building_hpbar(station)
		if station.powered <= 0 {
			draw_building_nopower(station)
		}
	},
	_is_place_on_water = proc() -> bool {
		return true
	},
	_define_hitpoint = proc() -> int { return 80 }
}

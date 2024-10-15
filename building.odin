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

Building :: struct {
	position : Vec2i,
	center : Vec2,// sorted by center.y before drew
	hitpoint_define : int,
	hitpoint : int,
	type : typeid,

	powered : int,// how many powerpump for this building

	using _vtable : ^Building_VTable,
	extra : rawptr,
}

Building_VTable :: struct {
	update : proc(handle: hla._HollowArrayHandle, delta: f64),
	draw : proc(handle: hla._HollowArrayHandle),
	extra_draw : proc(handle: hla._HollowArrayHandle),

	init : proc(b: ^Building),
	release : proc(b: ^Building),
}

building_init :: proc(b: ^Building) {
	if b.powered != -1 {// -1 means the building doesn't need power
		for p in hla.ites_alive_value(&game.buildings) {
			if p.type == PowerPump {
				p := cast(^PowerPump)p
				if linalg.distance(b.center, p.center) < auto_cast p.range {
					b.powered += 1
				}
			}
		}
	}
	b->init()
}
building_release :: proc(b: ^Building) {
	b->release()
}

building_get_cost :: proc(bt: typeid) -> int {
	if bt == Tower do return 200
	if bt == PowerPump do return 100
	return 0
}

draw_building_hpbar :: proc(using b: ^Building) {
	draw_hpbar({center.x-0.4, center.y+0.3, 0.8, 0.12}, cast(f32)hitpoint/cast(f32)hitpoint_define, 0.02)
}

package main

import "base:runtime"
import "core:fmt"
import "core:strconv"
import "core:mem"
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
	range : f64,

	using _vtable : ^Building_VTable(Building),
	extra : rawptr,
}

Building_VTable :: struct($T:typeid) {
	update : proc(building: ^T, delta: f64),
	pre_draw : proc(building: ^T),
	draw : proc(building: ^T),
	extra_draw : proc(building: ^T),

	preview_draw : proc(pos: Vec2i),

	init : proc(b: ^T),
	release : proc(b: ^T),

	_is_place_on_water : proc() -> bool,
	_define_hitpoint : proc() -> int,
}

Building_VTable_Empty :Building_VTable(Building)= {
	update = proc(building: ^Building, delta: f64) {},
	pre_draw = proc(building: ^Building) {},
	draw = proc(building: ^Building) {},
	extra_draw = proc(building: ^Building) {},

	preview_draw = proc(pos: Vec2i) {},

	init = proc(building: ^Building) {},
	release = proc(building: ^Building) {},

	_is_place_on_water = proc() -> bool { return false },
	_define_hitpoint = proc() -> int { return 150 }
}

// !!! where you register a new building type
_building_vtable :: proc(t: typeid) -> ^Building_VTable(Building) {
	if t == Tower do return auto_cast &_Tower_VTable
	if t == PowerPump do return auto_cast &_PowerPump_VTable
	if t == Minestation do return auto_cast &_Minestation_VTable
	if t == Mother do return auto_cast &_Mother_VTable
	if t == Wind do return auto_cast &_Wind_VTable
	if t == Probe do return auto_cast &_Probe_VTable
	if t == FogTower do return auto_cast &_FogTower_VTable
	if t == CannonTower do return auto_cast &_CannonTower_VTable
	return nil
}


building_new :: proc($T: typeid, position: Vec2i) -> ^T {
	t :^Building= cast(^Building)new(T)
	t._vtable = _building_vtable(T)
	t.type = T
	t.position = position
	t.center = Vec2{cast(f32)position.x, cast(f32)position.y} + {0.5, 0.5}
	t.hitpoint_define = t._vtable._define_hitpoint()
	t.hitpoint = t.hitpoint_define
	return auto_cast t
}

building_new_ :: proc(T: typeid, position: Vec2i) -> ^Building {
	ptr, _ := mem.alloc(type_info_of(T).size)
	t := cast(^Building)ptr
	t._vtable = _building_vtable(T)
	t.type = T
	t.position = position
	t.center = Vec2{cast(f32)position.x, cast(f32)position.y} + {0.5, 0.5}
	t.hitpoint_define = t._vtable._define_hitpoint()
	t.hitpoint = t.hitpoint_define
	return auto_cast t
}

building_init :: proc(b: ^Building) {
	if b.powered != -1 {// -1 means the building doesn't need power
		ite : int
		for p in hla.ite_alive_value(&game.buildings, &ite) {
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
	if bt == Tower do return 150
	if bt == PowerPump do return 60
	if bt == Minestation do return 40
	if bt == Wind do return 50
	if bt == Probe do return 15
	if bt == FogTower do return 180
	if bt == CannonTower do return 80
	return 0
}
// second
building_get_colddown :: proc(bt: typeid) -> f64 {
	if bt == Tower do return 10
	if bt == PowerPump do return 3
	if bt == Minestation do return 6
	if bt == Wind do return 1
	if bt == Probe do return 20
	if bt == FogTower do return 15
	if bt == CannonTower do return 5
	return 0
}

building_need_bomb_check :: proc(using b: ^Building) -> bool {
	if game.block[get_index(b.position.x, b.position.y)] == ITEM_BOMB {
		return true
	} else {
		hitpoint -= 1
		return false
	}
}

draw_building_hpbar :: proc(using b: ^Building) {
	draw_hpbar({center.x-0.4, center.y+0.3, 0.8, 0.12}, cast(f32)hitpoint/cast(f32)hitpoint_define, 0.02)
}

draw_building_nopower :: proc(using b: ^Building) {
	dest := rl.Rectangle{center.x,center.y, 1,1}
	shadow := dest; shadow.x += 0.05; shadow.y += 0.05
	alpha := math.abs(math.sin(game.time))
	rl.DrawTexturePro(game.res.no_power_tex, {0,0,32,32}, shadow, {0.5,0.5}, 0, {0,0,0, auto_cast (64.0*alpha)})
	rl.DrawTexturePro(game.res.no_power_tex, {0,0,32,32}, dest, {0.5,0.5}, 0, {255,255,255, auto_cast (255.0*alpha)})
}

package main

import "core:math/rand"
import "core:math/noise"
import "core:math/linalg"
import "core:math"
import rl "vendor:raylib"
import hla "collections/hollow_array"

Tower :: struct {
	using _ : Building,
	// define
	range : f64,
	shoot_interval : f64,

	// run
	shoot_charge : f64,
	target : BirdHandle,
}

tower_new :: proc(position: Vec2i) -> ^Tower {
	t :^Tower= new(Tower)
	t._vtable = &_Tower_VTable
	t.position = position
	t.center = Vec2{cast(f32)position.x, cast(f32)position.y} + {0.5, 0.5}
	t.range = 4 
	t.shoot_interval = 0.25
	return t
}

tower_free :: proc(ptr: ^Tower) {
	free(ptr)
}

@(private="file")
_tower_update :: proc(handle: hla._HollowArrayHandle, delta: f64) {
	using hla
	tower := hla_get_value(transmute(hla.HollowArrayHandle(^Tower))handle)

	if tower.shoot_charge < tower.shoot_interval {
		tower.shoot_charge += delta
	}

	tower_center :rl.Vector2= {cast(f32)tower.position.x + 0.5, cast(f32)tower.position.y + 0.5}
	
	if b, ok := hla.hla_get_pointer(tower.target); ok {
		if linalg.distance(b.pos, tower_center) > auto_cast tower.range {// 超出范围，丢失锁定
			tower.target = {}
		} else if tower.shoot_charge >= tower.shoot_interval {
			bird := hla.hla_get_pointer(tower.target)
			bird.hitpoint -= 10
			tower.shoot_charge = 0
		}
	} else {
		distance :f32= auto_cast tower.range
		for candi in hla.ites_alive_handle(&game.birds) {
			d := linalg.distance(hla.hla_get_pointer(candi).pos, tower_center)
			if d < auto_cast distance {
				distance = d
				tower.target = candi
				tower.shoot_charge = 0
			}
		}
	}
}
@(private="file")
_tower_draw :: proc(handle: hla._HollowArrayHandle) {
	using hla
	tower := hla_get_value(transmute(hla.HollowArrayHandle(^Tower))handle)
	tex := game.res.tower_tex
	height := cast(f32) tex.height
	rl.DrawCircleLinesV(tower.center, auto_cast tower.range, {255, 100, 100, 128})
	rl.DrawTexturePro(tex, {0,0,32, height}, {cast(f32)tower.position.x,cast(f32)tower.position.y, 1, height/32.0}, {0,1}, 0, rl.WHITE)
}
@(private="file")
_tower_extra_draw :: proc(handle: hla._HollowArrayHandle) {
	using hla
	tower := hla_get_value(transmute(hla.HollowArrayHandle(^Tower))handle)
	if target, ok := hla.hla_get_pointer(tower.target); ok {
		thickness :f32= auto_cast ((0.3-0.1)*(tower.shoot_charge/tower.shoot_interval)+0.1)
		rl.DrawLineEx(tower.center, target.pos+{0.5,0.5}, thickness, {80, 100, 160, 128})
		rl.DrawLineEx(tower.center, target.pos+{0.5,0.5}, thickness*0.4, {200, 230, 220, 255})
	}
}

@private
_Tower_VTable :Building_VTable= {
	update = _tower_update,
	draw = _tower_draw,
	extra_draw = _tower_extra_draw,
}

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

	_poweron : bool,
	collect_interval : f64,
	collect_time : f64,
	collect_amount : int,
}

@private
_Minestation_VTable :Building_VTable(Minestation)= {
	update = proc(station: ^Minestation, delta: f64) {
		using station
		if !building_need_bomb_check(station) do return
		poweron :bool= station.powered > 0
		if !_poweron && poweron {
			minestation_for_available_cells(station, proc(p: Vec2i) {
				game.mining[get_index(p.x, p.y)] += 1
			})
		}
		if _poweron && !poweron {
			minestation_for_available_cells(station, proc(p: Vec2i) {
				game.mining[get_index(p.x, p.y)] -= 1
			})
		}
		_poweron = poweron
	},
	init = proc(using station: ^Minestation) {
		range = 4
	},
	release = proc(station: ^Minestation) {
		bx, by := station.position.x, station.position.y
		if station._poweron {
			minestation_for_available_cells(station, proc(p: Vec2i) {
				game.mining[get_index(p.x, p.y)] -= 1
			})
		}
	},
	pre_draw = auto_cast Building_VTable_Empty.pre_draw,
	draw = proc(station: ^Minestation) {
		tex := game.res.minestation_tex
		height := cast(f32) tex.height
		rl.DrawTexturePro(tex, {0,0,32, height}, {cast(f32)station.position.x,cast(f32)station.position.y, 1, height/32.0}, {0,0}, 0, rl.WHITE)
	},
	extra_draw = proc(station: ^Minestation) {
		draw_building_hpbar(station)
		if station.powered <= 0 {
			draw_building_nopower(station)
		}
	},
	preview_draw = proc(pos: Vec2i) {
		rl.DrawCircleLinesV(get_center(pos), 4, {255, 100, 100, 128})
	},
	_is_place_on_water = proc() -> bool {
		return true
	},
	_define_hitpoint = proc() -> int { return 80 }
}

// Count how many minestations are available for the cell
count_minestations :: proc(pos: Vec2i) -> int {
	ite : int
	count : int
	for b in hla.ite_alive_value(&game.buildings, &ite) {
		if b.type == Minestation {
			station := cast(^Minestation)b
			if !station._poweron do continue
			if linalg.distance(b.center, Vec2{cast(f32)pos.x+0.5,cast(f32)pos.y+0.5}) <= cast(f32)station.range {
				count += 1
			}
		}
	}
	return count
}

minestation_for_available_cells :: proc(s: ^Minestation, process: proc(p:Vec2i)) {
	bx, by := s.position.x, s.position.y
	range := cast(int)s.range
	for x:=1; x<2*(range+1); x+=1 {
		X := bx + (1 if x%2==0 else -1) * x/2
		for y:=1; y<2*(range+1); y+=1 {
			using linalg
			Y := by + (1 if y%2==0 else -1) * y/2
			idx := get_index(X,Y)
			center := Vec2{cast(f32)X+0.5,cast(f32)Y+0.5}
			if game.sunken[idx] == 0 && in_range(X,Y) && distance(s.center, center) <= cast(f32)range {
				process({X,Y})
			}
		}
	}
}

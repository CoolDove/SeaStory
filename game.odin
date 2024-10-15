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

Game :: struct {
	block : [BLOCK_WIDTH*BLOCK_WIDTH]u32,
	mask : [BLOCK_WIDTH*BLOCK_WIDTH]u32,
	hitpoint : [BLOCK_WIDTH*BLOCK_WIDTH]f32,
	dead : bool,
	// towers : hla.HollowArray(Tower),
	buildings : hla.HollowArray(^Building),
	birds : hla.HollowArray(Bird),

	land : [dynamic][2]int,
	birdgen : BirdGenerator,

	time : f64,
	building_placing_colddown : [2]struct{
		time, duration : f64
	},// use PlacingMode as the index

	// gameplay resources
	mineral : int,

	res : GameResources,
	using operation : GameOperation,
}

PlacingMode :: enum {
	Tower, PowerPump
}

GameOperation :: struct {
	hover_cell : [2]int,
	last_position : rl.Vector2,
	mouse_position_drag_start : rl.Vector2,
	placing_mode : PlacingMode,
	placeable : bool,
}
GameResources :: struct {
	tower_tex : rl.Texture,
	power_pump_tex : rl.Texture,
	bird_tex : rl.Texture
}

Position :: struct {
	x, y : int,
}

game_add_bird :: proc(g: ^Game, p: rl.Vector2) {
	hla.hla_append(&g.birds, Bird{
		pos = p,
		hitpoint = 100,
		shoot_interval = 1.0,
	})
}

game_kill_bird :: proc(g: ^Game, b: hla.HollowArrayHandle(Bird)) {
	hla.hla_remove_handle(b)
}

sweep :: proc(using g: ^Game, x,y : int, peek:= false) {
	idx := get_index(x,y)
	m := mask[idx]
	v := block[idx]
	if m == 0 {
		mask[idx] = FLAG_TOUCHED
		append(&land, [2]int{x,y})
		hitpoint[idx] = 1.0
		if v == 0 {
			_sweep :: proc(g: ^Game, x,y: int) {
				if in_range(x,y) {
					sweep(g, x,y, true)
				}
			}
			_sweep(g, x-1,y-1)
			_sweep(g, x,y-1)
			_sweep(g, x+1,y-1)
			_sweep(g, x-1,y)
			// _sweep(g, x,y)
			_sweep(g, x+1,y)
			_sweep(g, x-1,y+1)
			_sweep(g, x,y+1)
			_sweep(g, x+1,y+1)
		} else if v == ITEM_BOMB {
			dead = true
		}
	}
}

mark_toggle :: proc(using g: ^Game, x,y : int) {
	idx := get_index(x,y)
	if mask[idx] == 0 {
		mask[idx] = FLAG_MARKED
	} else if mask[idx] == FLAG_MARKED {
		mask[idx] = 0
	}
}


game_init :: proc(using g: ^Game) {
	for i in 0..<160 do block[i] = ITEM_BOMB
	rand.shuffle(block[:])
	res.tower_tex = rl.LoadTexture("res/tower.png");
	res.bird_tex = rl.LoadTexture("res/bird.png");
	res.power_pump_tex = rl.LoadTexture("res/power_pump.png");

	buildings = hla.hla_make(^Building, 32)
	birdgen.interval = 0.5

	tool_colddown_init()
	tool_colddown_start()
}

game_release :: proc(using g: ^Game) {
	hla.hla_delete(&g.buildings)
}

game_update :: proc(using g: ^Game, delta: f64) {
	camera.offset = rl.Vector2{ cast(f32)rl.GetScreenWidth()*0.5, cast(f32)rl.GetScreenHeight()*0.5 }

	hover_world_position := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)
	hover_cell = {cast(int)hover_world_position.x, cast(int)hover_world_position.y}

	dragged_distance := linalg.distance(mouse_position_drag_start, rl.GetMousePosition())

	if rl.IsMouseButtonPressed(.MIDDLE) {
		last_position = rl.GetMousePosition()
		mouse_position_drag_start = last_position
	}
	if rl.IsMouseButtonDown(.MIDDLE) {
		last := rl.GetScreenToWorld2D(last_position, camera)
		now := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)
		camera.target += last-now
	} 


	if rl.IsKeyReleased(.Q) {
		game.placing_mode = .Tower
	} else if rl.IsKeyReleased(.W) {
		game.placing_mode = .PowerPump
	}

	placeable = false
	switch game.placing_mode {
	case .Tower:
		placeable = in_range(hover_cell.x, hover_cell.y) && mask[get_index(hover_cell.x, hover_cell.y)] == FLAG_TOUCHED
		placeable &= tool_colddown_get(.Tower) <= 0
	case .PowerPump:
		placeable = in_range(hover_cell.x, hover_cell.y) && mask[get_index(hover_cell.x, hover_cell.y)] != FLAG_TOUCHED
		placeable &= tool_colddown_get(.PowerPump) <= 0
	}

	if rl.IsMouseButtonReleased(.RIGHT) {
		mark_toggle(&game, hover_cell.x, hover_cell.y)
		switch game.placing_mode {
		case .Tower:
			if placeable {
				hla.hla_append(&g.buildings, tower_new(hover_cell))
				tool_colddown_start_by_mode(.Tower)
			}
		case .PowerPump:
			if placeable {
				hla.hla_append(&g.buildings, power_pump_new(hover_cell))
				tool_colddown_start_by_mode(.PowerPump)
			}
		}
	}

	if !dead && rl.IsMouseButtonReleased(.LEFT) {
		if in_range(hover_cell.x, hover_cell.y) {
			// ** sweep
			sweep(&game, hover_cell.x, hover_cell.y)
		}
	}

	_is_double_button :: proc(btn, btp: rl.MouseButton) -> bool {
		return rl.IsMouseButtonPressed(btn) && rl.IsMouseButtonDown(btp)
	}
	if _is_double_button(.LEFT,.RIGHT) || _is_double_button(.RIGHT,.LEFT) {

	}

	zoom_speed_max, zoom_speed_min :f32= 1.2, 0.2
	zoom_max, zoom_min :f32= 42, 18
	zoom_speed :f32= ((camera.zoom-zoom_min)/(zoom_max-zoom_min)) * ( zoom_speed_max-zoom_speed_min ) + zoom_speed_min
	camera.zoom += rl.GetMouseWheelMove() * zoom_speed
	camera.zoom = clamp(camera.zoom, zoom_min, zoom_max)

	last_position = rl.GetMousePosition()

	// bird gen
	birdgen_update(g, &g.birdgen, 1.0/64.0)

	for building_handle in hla.ites_alive_handle(&game.buildings) {
		building := hla.hla_get_pointer(building_handle)^
		building.update(transmute(hla._HollowArrayHandle)building_handle, delta)
	}

	for bird_handle in hla.ites_alive_handle(&g.birds) {
		bird_update(bird_handle, g, delta)
	}
	colddowns := game.building_placing_colddown
	for c in 0..<len(colddowns) {
		if colddowns[c].time > 0 {
			game.building_placing_colddown[c].time -= delta
		} else {
			game.building_placing_colddown[c].time = 0
		}
	}
	g.time += delta
}

tool_colddown_get :: proc(mode: PlacingMode) -> f64 {
	return game.building_placing_colddown[cast(int)mode].time
}
tool_colddown_start_by_mode :: proc(mode: PlacingMode) {
	tool_colddown_start(cast(int)mode)
}
tool_colddown_init :: proc() {
	game.building_placing_colddown[cast(int)PlacingMode.Tower].duration = 1.5
	game.building_placing_colddown[cast(int)PlacingMode.PowerPump].duration = 1.0
}
tool_colddown_start :: proc(index := -1/*-1 means all*/) {
	length := len(game.building_placing_colddown)
	if index < 0 || index >= length {
		for i in 0..<length do tool_colddown_start(i)
	} else {
		colddown := &game.building_placing_colddown[index]
		colddown.time = colddown.duration
	}
}

game_draw :: proc(using g: ^Game) {
	grid_color := rl.Color{68,160,156,128}
	for i in 0..=BLOCK_WIDTH {
		rl.DrawLineEx({auto_cast i, 0}, {auto_cast i, auto_cast BLOCK_WIDTH}, 0.1, grid_color)
		rl.DrawLineEx({0, auto_cast i}, {auto_cast BLOCK_WIDTH, auto_cast i}, 0.1, grid_color)
	}

	for x in 0..<BLOCK_WIDTH {
		for y in 0..<BLOCK_WIDTH {
			pos := rl.Vector2{cast(f32)x,cast(f32)y}
			n := noise.noise_2d(42, noise.Vec2{cast(f64)x,cast(f64)y}+0.6*{time, time})
			m := mask[get_index(cast(int)x,cast(int)y)]
			if m == FLAG_TOUCHED {
				points : [4]rl.Vector2
				points[0] = pos + {0.1, 0.1}
				points[1] = pos + {1.1, 0.1}
				points[2] = pos + {1.1, 1.1}
				points[3] = pos + {0.1, 1.1}
				for i in 0..<4 {
					p := points[i]
					points[i] = p + 0.04 * noise.noise_2d(42, noise.Vec2{cast(f64)p.x,cast(f64)p.y}+0.6*{time, time})
				}
				rl.DrawTriangle( points[0], points[2], points[1] , {0,0,0, 64})
				rl.DrawTriangle( points[0], points[3], points[2] , {0,0,0, 64})
			}
		}
	}

	for x in 0..<BLOCK_WIDTH {
		for y in 0..<BLOCK_WIDTH {
			draw_cell(g, auto_cast x, auto_cast y)
		}
	}

	if dead do rl.DrawRectangleV({0,0}, {cast(f32)BLOCK_WIDTH, cast(f32)BLOCK_WIDTH}, {255,60,60, 80})

	rl.DrawLine(-100, 0, 100, 0, rl.Color{255,255,0, 255})
	rl.DrawLine(0, -100, 0, 100, rl.Color{0,255,0, 255})

	// draw cursor
	hover_cell_corner := Vec2{cast(f32)hover_cell.x, cast(f32)hover_cell.y}
	rl.DrawRectangleV(hover_cell_corner, {0.9, 0.9}, {255,255,255, 80})
	if placeable do rl.DrawCircleV(hover_cell_corner+{0.5,0.5}, 0.4, {20, 240, 20, 90})

	for bird in hla.ites_alive_ptr(&g.birds) {
		x := cast(f32)bird.pos.x
		y := cast(f32)bird.pos.y
		rl.DrawTexturePro(res.bird_tex, {0,0,32,32}, {x+0.2,y+0.2, 1, 1}, {0,0}, 0, {0,0,0, 64})// shadow
		rl.DrawTexturePro(res.bird_tex, {0,0,32,32}, {x,y, 1, 1}, {0,0}, 0, rl.WHITE)
	}

	draw_elems := make([dynamic]DrawElem); defer delete(draw_elems)

	for building_handle in hla.ites_alive_handle(&game.buildings) {
		handle := new(hla._HollowArrayHandle)
		handle^ = transmute(hla._HollowArrayHandle)building_handle
		if building, ok := hla.hla_get_value(building_handle); ok {
			append(&draw_elems, DrawElem{
				handle,
				auto_cast building.position.y,
				proc(handle: rawptr) {
					using hla
					handleptr := cast(^HollowArrayHandle(^Building))handle
					building := hla_get_value(handleptr^)
					if building, ok := hla_get_value(handleptr^); ok {
						building.draw(transmute(hla._HollowArrayHandle)handleptr^)
					}
				},
				proc(handle: rawptr) {
					using hla
					handleptr := cast(^HollowArrayHandle(^Building))handle
					if building, ok := hla_get_value(handleptr^); ok {
						building.extra_draw(transmute(hla._HollowArrayHandle)handleptr^)
					}
				},
				proc(handle: rawptr) {
					using hla
					handleptr := cast(^hla._HollowArrayHandle)handle
					free(handleptr)
				}
			})
		}
	}

	slice.sort_by_cmp(draw_elems[:], proc(a, b: DrawElem) -> slice.Ordering {
		if a.order > b.order do return .Greater
		else if a.order < b.order do return .Less
		else do return .Equal
	})

	for e in draw_elems {
		e.draw(e.data)
	}
	for e in draw_elems {
		e.extra_draw(e.data)
	}

	draw_cell :: proc(using g: ^Game, x,y: int) {
		idx := get_index(x,y)
		v,m := block[idx], mask[idx]
		pos :rl.Vector2= {cast(f32)x,cast(f32)y}
		if m == 0 {
			// rl.DrawRectangleV(pos, {0.9, 0.9}, {155,155,155,255})
			// rl.DrawRectangleV(pos, {0.8, 0.8}, {200,200,200,255})
		} else if m == FLAG_MARKED {
			// rl.DrawRectangleV(pos, {0.9, 0.9}, {155,155,155,255})
			// rl.DrawRectangleV(pos, {0.8, 0.8}, {200,200,200,255})
			// draw flag
			triangle := [3]rl.Vector2{ {0,0}, {0,0.4}, {0.4,0.2} }
			offset := rl.Vector2{0.3, 0.1}
			for &p in triangle do p += offset + pos

			// shadow
			soffset := rl.Vector2{0.03,0.03}
			rl.DrawTriangle(triangle[0]+soffset, triangle[1]+soffset, triangle[2]+soffset, {0,0,0,100})
			rl.DrawRectangleV(pos+offset+soffset, {0.08, 0.7}, {0,0,0,100})

			rl.DrawTriangle(triangle[0], triangle[1], triangle[2], {230,20,10,255})
			rl.DrawRectangleV(pos+offset, {0.08, 0.7}, {60,50,20, 255})
		} else if m == FLAG_TOUCHED {
			if v == ITEM_BOMB {
				rl.DrawRectangleV(pos, {0.9, 0.9}, {100,100,100,255})
				rl.DrawRectangleV(pos, {0.8, 0.8}, {80,80,60,255})
				rl.DrawCircleV(pos+{0.4,0.4}, 0.3, {200, 70, 40, 255})
			} else if v == ITEM_QUESTION {
				rl.DrawRectangleV(pos, {1,1}, {217, 160, 102, 255})
				if v != 0 {
					rl.DrawTextEx(rl.GetFontDefault(), "?",
						pos+{0.2, 0.1}, 0.8, 1, rl.Color{200, 190, 40, 200})
				}
			} else {
				rl.DrawRectangleV(pos, {1,1}, {217, 160, 102, 255})
				if v != 0 {
					rl.DrawTextEx(rl.GetFontDefault(), fmt.ctprintf("{}", v),
						pos+{0.2, 0.1}, 0.8, 1, rl.Color{200, 140, 85, 200})
				}
			}
		}
	}
}

draw_ui :: proc() {
	viewport := Vec2{cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()}

	card_width :f32= 50
	card_height :f32= 60

	rect :rl.Rectangle= { 10, viewport.y - card_height - 10, card_width, card_height }

	draw_mode_card("炮塔", "Q", &rect, .Tower)
	draw_mode_card("能量泵", "W", &rect, .PowerPump)

	draw_mode_card :: proc(name, key: cstring, rect: ^rl.Rectangle, e: PlacingMode) {
		shadow_rect := rect^
		shadow_rect.x += 8
		shadow_rect.y += 8
		selected := game.placing_mode == e
		rl.DrawRectangleRec(shadow_rect, {0,0,0, 64})
		if selected {;
			framer := rect^
			framer.x -= 4
			framer.y -= 4
			framer.width += 8
			framer.height += 8
			rl.DrawRectangleRec(framer, {170, 190, 40, 200})
		}
		rl.DrawRectangleRec(rect^, {60,60,60, 255})

		colddown_rect := rect^
		colddown := &game.building_placing_colddown[cast(int)e]
		colddown_rect.height *= 1-cast(f32)(colddown.time/ colddown.duration);
		rl.DrawRectangleRec(colddown_rect, {200, 200, 200, 255})

		measure := rl.MeasureTextEx(FONT_DEFAULT, name, 20, 1)
		rl.DrawTextEx(FONT_DEFAULT, name, {rect.x, rect.y} + {0, measure.y - 20}, 20, 1, rl.BLACK)

		measure = rl.MeasureTextEx(FONT_DEFAULT, key, 20, 1)
		rl.DrawTextEx(FONT_DEFAULT, key, {rect.x, rect.y + rect.width - 20}, 20, 1, rl.GRAY)

		rect.x += rect.width + 10
	}
}

DrawElem :: struct {
	data : rawptr,
	order : f64,
	draw : proc(data: rawptr),
	extra_draw : proc(data: rawptr),
	free : proc(data: rawptr)
}

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
	towers : hla.HollowArray(Tower),
	birds : hla.HollowArray(Bird),

	land : [dynamic][2]int,

	birdgen : BirdGenerator,

	time : f64,

	res : GameResources,
	using operation : GameOperation,
}

GameOperation :: struct {
	hover_cell : [2]int,
	last_position : rl.Vector2,
	mouse_position_drag_start : rl.Vector2,
}
GameResources :: struct {
	tower_tex : rl.Texture,
	bird_tex : rl.Texture
}

Position :: struct {
	x, y : int,
}

game_add_tower :: proc(g: ^Game, p: Position) -> bool {
	using hla
	ite : hla.HollowArrayIterator
	for t in hla.hla_ite(&g.towers, &ite) {
		if t.pos == p do return false
	}
	hla_append(&g.towers, Tower{pos=p, range=4, shoot_interval=1})
	return true
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

	towers = hla.hla_make(Tower, 32)
	birdgen.interval = 0.5
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

	if rl.IsMouseButtonReleased(.RIGHT) {
		mark_toggle(&game, hover_cell.x, hover_cell.y)
		if mask[get_index(hover_cell.x, hover_cell.y)] != FLAG_TOUCHED {
			game_add_tower(g, {hover_cell.x, hover_cell.y})
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

	for b in hla.ites_alive_ptr(&g.birds) {
		bird_update(b, g, delta)
	}
	for t in hla.ites_alive_ptr(&g.towers) {
		tower_update(t, g, delta)
	}

	g.time += delta
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

	rl.DrawRectangleV({cast(f32)hover_cell.x, cast(f32)hover_cell.y}, {0.9, 0.9}, {255,255,255, 80})

	for bird in hla.ites_alive_ptr(&g.birds) {
		rl.DrawTexturePro(res.bird_tex, {0,0,32,32}, {cast(f32)bird.pos.x,cast(f32)bird.pos.y, 1, 1}, {0,0}, 0, rl.WHITE)
	}

	draw_towers := make([dynamic]^Tower)
	for t in hla.ites_alive_ptr(&g.towers) { append(&draw_towers, t) }

	slice.sort_by_cmp(draw_towers[:], proc(a, b: ^Tower) -> slice.Ordering {
		if a.pos.y > b.pos.y do return .Greater
		else if a.pos.y < b.pos.y do return .Less
		else do return .Equal
	})

	for tower in draw_towers {
		center :rl.Vector2= {cast(f32)tower.pos.x + 0.5, cast(f32)tower.pos.y + 0.5}
		rl.DrawCircleLinesV(center, auto_cast tower.range, rl.RED)
		draw_building(g, tower.pos.x, tower.pos.y, res.tower_tex)
		if target, ok := hla.hla_get_pointer(tower.target); ok {
			thickness :f32= auto_cast ((0.3-0.1)*(tower.shoot_charge/tower.shoot_interval)+0.1)
			rl.DrawLineEx(center, target.pos+{0.5,0.5}, thickness, {200, 100, 20, 64})
		}
	}

	draw_ui(g)

	// building is always a 32*n picture
	draw_building :: proc(using g: ^Game, x,y: int, tex: rl.Texture) {
		height := cast(f32) tex.height
		rl.DrawTexturePro(tex, {0,0,32, height}, {cast(f32)x,cast(f32)y, 1, height/32.0}, {0,1}, 0, rl.WHITE)
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

draw_ui :: proc(g: ^Game) {

}

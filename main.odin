package main

import "core:fmt"
import "core:strconv"
import "core:slice"
import "core:math/rand"
import "core:math/linalg"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

camera : rl.Camera2D

BLOCK_WIDTH :u32: 32
block : [BLOCK_WIDTH*BLOCK_WIDTH]u32
mask : [BLOCK_WIDTH*BLOCK_WIDTH]u32

dead : bool

rnd : rand.Rand

ITEM_BOMB :u32= 0xff

FLAG_MARKED :u32= 0xef
FLAG_TOUCHED :u32= 1

get_index :: proc(x,y: int) -> int {
	return x+y*(auto_cast BLOCK_WIDTH)
}

in_range :: proc(x,y: int) -> bool {
	w :int= cast(int)BLOCK_WIDTH
	return !(x < 0 || y < 0 || x >= w || y >= w)
}

main :: proc() {
	rl.SetConfigFlags({rl.ConfigFlag.WINDOW_RESIZABLE})
	rl.InitWindow(800, 600, "Minesweeper")

	rl.SetTargetFPS(60)

	camera.zoom = 20

	rand.init(&rnd, 42)

	for i in 0..<160 do block[i] = ITEM_BOMB

	rand.shuffle(block[:], &rnd)

	for x in 0..<BLOCK_WIDTH {
		for y in 0..<BLOCK_WIDTH {
			check :: proc(count: ^int, x,y: int) {
				if in_range(x,y) && block[get_index(x,y)] == ITEM_BOMB {
					count ^= count^ + 1
				}
			}
			x, y :int= auto_cast x, auto_cast y
			if block[get_index(x,y)] == ITEM_BOMB do continue
			count : int
			check(&count, x-1, y-1)
			check(&count, x, y-1)
			check(&count, x+1, y-1)

			check(&count, x-1, y)
			// check(&count, x, y)
			check(&count, x+1, y)

			check(&count, x-1, y+1)
			check(&count, x, y+1)
			check(&count, x+1, y+1)
			block[get_index(x,y)] = cast(u32)count
		}
	}

	last_position : rl.Vector2
	mouse_position_drag_start : rl.Vector2

	for !rl.WindowShouldClose() {
		camera.offset = rl.Vector2{ cast(f32)rl.GetScreenWidth()*0.5, cast(f32)rl.GetScreenHeight()*0.5 }

		speed :f32= 0.2
		if rl.IsKeyDown(.A) {
			camera.target.x -= speed
		} else if rl.IsKeyDown(.D) {
			camera.target.x += speed
		}
		if rl.IsKeyDown(.W) {
			camera.target.y -= speed
		} else if rl.IsKeyDown(.S) {
			camera.target.y += speed
		}

		hover_world_position := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)
		hover_cell :[2]int= {cast(int)hover_world_position.x, cast(int)hover_world_position.y}

		if rl.IsMouseButtonPressed(.RIGHT) {
			last_position = rl.GetMousePosition()
			mouse_position_drag_start = last_position
		}
		if rl.IsMouseButtonDown(.RIGHT) {
			last := rl.GetScreenToWorld2D(last_position, camera)
			now := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)
			camera.target += last-now
		} else if rl.IsMouseButtonReleased(.RIGHT) {
			dragged_distance := linalg.distance(mouse_position_drag_start, rl.GetMousePosition())
			if dragged_distance < 4 {
				mark_toggle(hover_cell.x, hover_cell.y)
			}
		}

		if !dead && rl.IsMouseButtonReleased(.LEFT) {
			if in_range(hover_cell.x, hover_cell.y) {
				// ** sweep
				sweep(hover_cell.x, hover_cell.y)
			}
		}
		if dead && rl.IsKeyPressed(.R) {
			for i in 0..<len(mask) do mask[i] = 0
			dead = false
		}

		zoom_speed_max, zoom_speed_min :f32= 1.2, 0.2
		zoom_max, zoom_min :f32= 36, 18
		zoom_speed :f32= ((camera.zoom-zoom_min)/(zoom_max-zoom_min)) * ( zoom_speed_max-zoom_speed_min ) + zoom_speed_min
		camera.zoom += rl.GetMouseWheelMove() * zoom_speed
		camera.zoom = clamp(camera.zoom, zoom_min, zoom_max)

		last_position = rl.GetMousePosition()

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{0,0,0,0})

		rl.BeginMode2D(camera)

		for x in 0..<BLOCK_WIDTH {
			for y in 0..<BLOCK_WIDTH {
				idx := get_index(cast(int)x,cast(int)y)
				v,m := block[idx], mask[idx]
				pos :rl.Vector2= {cast(f32)x,cast(f32)y}
				if m == 0 {
					rl.DrawRectangleV(pos, {0.9, 0.9}, {155,155,155,255})
					rl.DrawRectangleV(pos, {0.8, 0.8}, {200,200,200,255})
				} else if m == FLAG_MARKED {
					rl.DrawRectangleV(pos, {0.9, 0.9}, {155,155,155,100})
					rl.DrawRectangleV(pos, {0.8, 0.8}, {200,200,200,100})
				} else if m == FLAG_TOUCHED {
					if v == ITEM_BOMB {
						rl.DrawRectangleV(pos, {0.9, 0.9}, {100,100,100,255})
						rl.DrawRectangleV(pos, {0.8, 0.8}, {80,80,60,255})
						rl.DrawCircleV(pos+{0.4,0.4}, 0.3, {200, 70, 40, 255})
					} else {
						rl.DrawRectangleV(pos, {0.9, 0.9}, {100,100,100,255})
						rl.DrawRectangleV(pos, {0.8, 0.8}, {80,80,80,255})
						if v != 0 {
							rl.DrawTextEx(rl.GetFontDefault(), fmt.ctprintf("{}", v),
								pos+{0.2, 0.1}, 0.8, 1, rl.Color{80, 120, 90, 255})
						}
					}
				}
			}
		}

		rl.DrawRectangleV({cast(f32)hover_cell.x, cast(f32)hover_cell.y}, {0.9, 0.9}, {255,255,255, 80})

		if dead do rl.DrawRectangleV({0,0}, {cast(f32)BLOCK_WIDTH, cast(f32)BLOCK_WIDTH}, {255,60,60, 80})

		rl.DrawLine(-100, 0, 100, 0, rl.Color{255,255,0, 255})
		rl.DrawLine(0, -100, 0, 100, rl.Color{0,255,0, 255})

		rl.EndMode2D()

		debug_color := rl.Color{0,255,0,255}
		rl.DrawText(fmt.ctprintf("zoom: {}", camera.zoom), 10, 10+30, 28, debug_color)
		rl.DrawText(fmt.ctprintf("target: {}", camera.target), 10, 10+30+30, 28, debug_color)
		rl.DrawText(fmt.ctprintf("offset: {}", camera.offset), 10, 10+30+30*2, 28, debug_color)

		rl.EndDrawing()

		// _draw_flag :: proc(root: rl.Vector2, height: f32, color: rl.Color) {
		// 	rl.DrawTriangle(, color)
		// }
	}
	rl.CloseWindow()
}

sweep :: proc(x,y : int, peek:= false) {
	idx := get_index(x,y)
	m := mask[idx]
	v := block[idx]
	if m == 0 {
		mask[idx] = FLAG_TOUCHED
		if v == 0 {
			_sweep :: proc(x,y: int) {
				if in_range(x,y) {
					sweep(x,y, true)
				}
			}
			_sweep(x-1,y-1)
			_sweep(x,y-1)
			_sweep(x+1,y-1)
			_sweep(x-1,y)
			// _sweep(x,y)
			_sweep(x+1,y)
			_sweep(x-1,y+1)
			_sweep(x,y+1)
			_sweep(x+1,y+1)
		} else if v == ITEM_BOMB {
			dead = true
		}
	}
}

mark_toggle :: proc(x,y : int) {
	idx := get_index(x,y)
	if mask[idx] == 0 {
		mask[idx] = FLAG_MARKED
	} else if mask[idx] == FLAG_MARKED {
		mask[idx] = 0
	}
}

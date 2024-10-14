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
import "core:unicode/utf8"
import rl "vendor:raylib"

camera : rl.Camera2D

BLOCK_WIDTH :u32: 32

ITEM_BOMB :u32= 0xff
ITEM_QUESTION :u32= 0xfe

FLAG_MARKED :u32= 0xef
FLAG_TOUCHED :u32= 1

game : Game


// types
Vec2 :: rl.Vector2
Vec2i :: [2]int


FONT_DEFAULT : rl.Font

get_index :: proc(x,y: int) -> int {
	return x+y*(auto_cast BLOCK_WIDTH)
}

in_range :: proc(x,y: int) -> bool {
	w :int= cast(int)BLOCK_WIDTH
	return !(x < 0 || y < 0 || x >= w || y >= w)
}

@(private="file")
_data_font := #load("smiley.ttf", []u8)
@(private="file")
_data_charsheet := #load("char_sheet.txt", string)

main :: proc() {
	rl.SetConfigFlags({rl.ConfigFlag.WINDOW_RESIZABLE})
	rl.InitWindow(800, 600, "Minesweeper")

	rl.SetTargetFPS(60)


	{// load font
		runes := utf8.string_to_runes(_data_charsheet, context.temp_allocator)
		FONT_DEFAULT = rl.LoadFontFromMemory(
			".ttf", 
			raw_data(_data_font), 
			cast(i32)len(_data_font), 
			32, 
			&runes[0], 
			cast(i32)len(runes))
	}



	camera.zoom = 20

	rand.reset(42)

	game_init(&game)

	for x in 0..<BLOCK_WIDTH {
		for y in 0..<BLOCK_WIDTH {
			using game
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
			if count > 0 && rand.float32() < 0.2 {
				block[get_index(x,y)] = ITEM_QUESTION
			}
		}
	}

	for !rl.WindowShouldClose() {
		game_update(&game, 1.0/60.0)

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{78,180,166,0})

		rl.BeginMode2D(camera)
		game_draw(&game)
		rl.EndMode2D()
		draw_ui()

		debug_color := rl.Color{0,255,0,255}
		rl.DrawText(fmt.ctprintf("zoom: {}", camera.zoom), 10, 10+30, 28, debug_color)
		rl.DrawText(fmt.ctprintf("target: {}", camera.target), 10, 10+30+30, 28, debug_color)
		rl.DrawText(fmt.ctprintf("offset: {}", camera.offset), 10, 10+30+30*2, 28, debug_color)

		rl.EndDrawing()
		free_all(context.temp_allocator)
	}
	rl.CloseWindow()
}

CellInfo :: struct {
	block, mask : u32
}
GameBlock :: #soa [BLOCK_WIDTH*BLOCK_WIDTH]CellInfo

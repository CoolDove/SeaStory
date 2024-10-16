package main

import "base:runtime"
import "core:fmt"
import "core:mem"
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
game_end : bool

// types
Vec2 :: rl.Vector2
Vec2i :: [2]int


GAME_DEBUG : bool = true

FONT_DEFAULT : rl.Font

get_index :: proc {
	get_indexi,
	get_indexv,
}
get_indexi :: proc(x,y: int) -> int {
	return x+y*(auto_cast BLOCK_WIDTH)
}
get_indexv :: proc(pos: Vec2i) -> int {
	return pos.x+pos.y*(auto_cast BLOCK_WIDTH)
}

in_range :: proc {
	in_rangei,
	in_rangev,
}
in_rangei :: proc(x,y: int) -> bool {
	w :int= cast(int)BLOCK_WIDTH
	return !(x < 0 || y < 0 || x >= w || y >= w)
}
in_rangev :: proc(pos: Vec2i) -> bool {
	w :int= cast(int)BLOCK_WIDTH
	return !(pos.x < 0 || pos.y < 0 || pos.x >= w || pos.y >= w)
}

@(private="file")
_data_font := #load("smiley.ttf", []u8)
@(private="file")
_data_charsheet := #load("char_sheet.txt", string)

@(private="file")
_track : mem.Tracking_Allocator

main :: proc() {
	mem.tracking_allocator_init(&_track, context.allocator)
	context.allocator = mem.tracking_allocator(&_track)

	defer {
		for _, entry in _track.allocation_map {
			fmt.printf("{} leaked: {}\n", entry.location, entry.size)
		}
		for entry in _track.bad_free_array {
			fmt.printf("{} bad free: {}\n", entry.location)
		}
		mem.tracking_allocator_destroy(&_track)
	}

	rl.SetConfigFlags({rl.ConfigFlag.WINDOW_RESIZABLE})
	rl.InitWindow(800, 600, "Minesweeper")

	rl.SetTargetFPS(60)
	rl.SetExitKey(auto_cast 0)


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

	camera.zoom = 36

	game_init(&game)

	for !rl.WindowShouldClose() && !game_end {
		camera.offset = rl.Vector2{ cast(f32)rl.GetScreenWidth()*0.5, cast(f32)rl.GetScreenHeight()*0.5 }
		if rl.IsKeyPressed(.F1) do GAME_DEBUG = !GAME_DEBUG
		game_update(&game, 1.0/60.0)

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{78,180,166,0})

		rl.BeginMode2D(camera)
		game_draw(&game)
		rl.EndMode2D()
		draw_ui()

		if GAME_DEBUG {
			debug_color := rl.Color{0,255,0,255}
			rl.DrawText(fmt.ctprintf("zoom: {}", camera.zoom), 10, 10+30, 28, debug_color)
			rl.DrawText(fmt.ctprintf("target: {}", camera.target), 10, 10+30+30, 28, debug_color)
			rl.DrawText(fmt.ctprintf("offset: {}", camera.offset), 10, 10+30+30*2, 28, debug_color)
			rl.DrawText(fmt.ctprintf("hover cell: {}", game.hover_cell), 10, 10+30+30+30*2, 28, debug_color)
		}

		rl.EndDrawing()
		free_all(context.temp_allocator)
	}
	game_release(&game)

	rl.CloseWindow()
}

CellInfo :: struct {
	block, mask : u32
}
GameBlock :: #soa [BLOCK_WIDTH*BLOCK_WIDTH]CellInfo

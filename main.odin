package main

import "base:runtime"
import "core:fmt"
import "core:reflect"
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
import tw "tween"

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
Vec3 :: rl.Vector3
Vec3i :: [3]int


when ODIN_DEBUG {
	GAME_DEBUG : bool = true
} else {
	GAME_DEBUG : bool = false
}

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

get_center :: proc(v: Vec2i) -> Vec2 {
	return {auto_cast v.x + 0.5, auto_cast v.y + 0.5}
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


ENEMY_ATK_COLOR :rl.Color = {240,10,10, 255}
PLAYER_ATK_COLOR :rl.Color = {200,220,240, 255}

main :: proc() {
	mem.tracking_allocator_init(&_track, context.allocator)
	context.allocator = mem.tracking_allocator(&_track)

	defer {
		for _, entry in _track.allocation_map {
			fmt.printf("{} leaked: {}\n", entry.location, entry.size)
		}
		for entry in _track.bad_free_array {
			fmt.printf("bad free: {}\n", entry.location)
		}
		mem.tracking_allocator_destroy(&_track)
	}

	rl.SetConfigFlags({rl.ConfigFlag.WINDOW_RESIZABLE})
	rl.InitWindow(800, 600, "Minesweeper")
	rl.InitAudioDevice()

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
			line :Vec2= {10, 10}
			_debug_line(fmt.tprintf("zoom: {}", camera.zoom), &line)
			_debug_line(fmt.tprintf("target: {}", camera.target), &line)
			_debug_line(fmt.tprintf("offset: {}", camera.offset), &line)
			_debug_line(fmt.tprintf("hover cell: {}", game.hover_cell), &line)
			_debug_line(fmt.tprintf("tweens: {}", tw.tweener_count(&game.tweener)), &line)
			_debug_line(fmt.tprintf("vfx: {}/{}", game.vfx.count, cap(game.vfx.buffer)), &line)

			_debug_line :: proc(msg: string, line: ^Vec2) {
				rl.DrawText(strings.clone_to_cstring(msg, context.temp_allocator), auto_cast line.x, auto_cast line.y, 28, {0,255,0,255})
				line.y += 30
			}
		}

		rl.EndDrawing()
		free_all(context.temp_allocator)
	}
	game_release(&game)

	rl.CloseAudioDevice()
	rl.CloseWindow()
}

CellInfo :: struct {
	block, mask : u32
}
GameBlock :: #soa [BLOCK_WIDTH*BLOCK_WIDTH]CellInfo

// ite.x: round count, ite.y: step count
ite_around :: proc(c: Vec2i, round: int, ite: ^[3]int) -> (Vec2i, bool) {
	if ite.x == 0 do ite.x = 1
	res : Vec2i
	succ : bool
	r := ite.x
	s := ite.y
	if r >= round do return {}, false
	if s == 0 {
		i := ite.z
		_step(ite, round)
		return c+{i-r, r}, true
	} else if s == 1 {
		i := ite.z
		_step(ite, round)
		return c+{r, 1-r+i}, true
	} else if s == 2 {
		i := ite.z
		_step(ite, round)
		return c+{r-i, -r}, true
	} else if s == 3 {
		i := ite.z
		_step(ite, round)
		return c+{-r, -r+i}, true
	}
	return {}, false

	_step :: proc(ite: ^[3]int, round: int) {
		ite.z += 1
		if ite.z == ite.x*2 {
			ite.z = 0
			ite.y += 1
			if ite.y == 4 {
				ite.y = 0
				ite.x += 1
			}
		}
	}
}

load_resource :: proc(res: ^$T) {
	info := type_info_of(T)
	if !reflect.is_struct(info) do return
	offsets := reflect.struct_field_offsets(T)
	names := reflect.struct_field_names(T)
	types := reflect.struct_field_types(T)
	fields := soa_zip(offset=offsets, name=names, type=types)

	for f in fields {
		using f
		if type.id == typeid_of(rl.Texture) {
			ptr :^rl.Texture = cast(^rl.Texture)(cast(uintptr)res+offset)
			name := strings.trim_suffix(name, "_tex")
			ptr^ = rl.LoadTexture(fmt.ctprintf("res/{}.png", name))
		} else if type.id == typeid_of(rl.Sound) {
			ptr :^rl.Sound = cast(^rl.Sound)(cast(uintptr)res+offset)
			ptr^ = rl.LoadSound(fmt.ctprintf("res/{}.mp3", name))
		}
	}
}

unload_resource :: proc(res: ^$T) {
	info := type_info_of(T)
	if !reflect.is_struct(info) do return
	offsets := reflect.struct_field_offsets(T)
	names := reflect.struct_field_names(T)
	types := reflect.struct_field_types(T)
	fields := soa_zip(offset=offsets, name=names, type=types)

	for f in fields {
		using f
		if type.id == typeid_of(rl.Texture) {
			ptr :^rl.Texture = cast(^rl.Texture)(cast(uintptr)res+offset)
			rl.UnloadTexture(ptr^)
		} else if type.id == typeid_of(rl.Sound) {
			ptr :^rl.Sound = cast(^rl.Sound)(cast(uintptr)res+offset)
			rl.UnloadSound(ptr^)
		}
	}
}

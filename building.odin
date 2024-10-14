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
	hitpoint : int,

	tex : rl.Texture,
	using _vtable : ^Building_VTable,
	extra : rawptr,
}

Building_VTable :: struct {
	update : proc(handle: hla._HollowArrayHandle, delta: f64),
	draw : proc(handle: hla._HollowArrayHandle),
	extra_draw : proc(handle: hla._HollowArrayHandle),
}

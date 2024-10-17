package main
import rl "vendor:raylib"
import hla "collections/hollow_array"
import "collections/pool"
import tw "tween"
import "core:fmt"
import "core:math"

draw_hpbar :: proc(rect: rl.Rectangle, p: f32, frame_thickness:f32=0) {
	rl.DrawRectangleRec(rect, rl.RED)
	fill := rect
	fill.width *= p
	rl.DrawRectangleRec(fill, rl.GREEN)
	if frame_thickness > 0 do rl.DrawRectangleLinesEx(rect, frame_thickness, rl.WHITE)
}

vfx_number :: proc(p: Vec2, n: int, color:rl.Color) {
	VfxNumberText :: struct {
		using __base : _VfxBase,
		life : f64,
		number : int,
		center : Vec2,
		color : rl.Color,
	}
	vfxh := hla.hla_append(&game.vfx, Vfx{})
	vfx := hla.hla_get_pointer(vfxh)
	vfx^ = vfx_create(
		proc(v: ^Vfx, delta: f64) {
			v := cast(^VfxNumberText)v
			if v.life <= 0 do v.die = true
		},
		eextra_draw(vfx, auto_cast proc(vfx: ^VfxNumberText) {
			alpha :u8= cast(u8)(255.0 * vfx.life)
			str := fmt.ctprintf("{}", vfx.number)
			font := rl.GetFontDefault()
			size :f32= 0.6
			spacing :f32= 0.05
			measure := rl.MeasureTextEx(font, str, size, spacing)
			pos := vfx.center-{measure.x*0.5, 0}
			pos += {0, -0.5*(1-cast(f32)vfx.life)}

			scol :rl.Color= {0,0,0, cast(u8)(64.0*(1-vfx.life))}
			rl.DrawTextEx(font, str, pos+{0.02,0.02}, size, spacing, scol)
			rl.DrawTextEx(font, str, pos+{-0.02,0.02}, size, spacing, scol)
			rl.DrawTextEx(font, str, pos+{-0.02,-0.02}, size, spacing, scol)
			rl.DrawTextEx(font, str, pos+{0.02,-0.02}, size, spacing, scol)
			col := vfx.color
			rl.DrawTextEx(font, str, pos, size, spacing, col)
		})
	)
	num := cast(^VfxNumberText)vfx
	num.color = color
	num.number = n
	num.life = 1.0
	num.center = p+{0.5,0.5}
	tw.tween(&game.tweener, &num.life, 0, 0.6, tw.ease_inoutcirc)
}

vfx_boom :: proc(center: Vec2, range: f32, duration: f32) {
	VfxBoom :: struct {
		using __base : _VfxBase,
		center : Vec2,
		range : f32,
		life : f32,
	}
	vfxh := hla.hla_append(&game.vfx, Vfx{})
	vfx := hla.hla_get_pointer(vfxh)
	vfx^ = vfx_create(
		proc(v: ^Vfx, delta: f64) {
			v := cast(^VfxBoom)v
			if v.life <= 0 do v.die = true
		},
		eextra_draw(vfx, auto_cast proc(vfx: ^VfxBoom) {
			alpha :u8= cast(u8)(255.0 * vfx.life)
			rl.DrawCircleV(vfx.center, vfx.range+vfx.range*0.5*(1-vfx.life), {128,128,128, alpha/2})
			rl.DrawCircleV(vfx.center, vfx.range, {255,255,255, alpha})
		})
	)
	boom := cast(^VfxBoom)vfx
	boom.life = 1.0
	boom.center = center
	boom.range = range
	tw.tween(&game.tweener, &boom.life, 0, duration, tw.ease_outcirc)
}

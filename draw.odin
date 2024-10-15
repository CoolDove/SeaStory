package main
import rl "vendor:raylib"

draw_hpbar :: proc(rect: rl.Rectangle, p: f32, frame_thickness:f32=0) {
	rl.DrawRectangleRec(rect, rl.RED)
	fill := rect
	fill.width *= p
	rl.DrawRectangleRec(fill, rl.GREEN)
	if frame_thickness > 0 do rl.DrawRectangleLinesEx(rect, frame_thickness, rl.WHITE)
}

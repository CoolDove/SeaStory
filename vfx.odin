package main

Vfx :: struct {
	using __base : _VfxBase,
	__reserve : [128]u8,
}

_VfxBase :: struct {
	using draw_elem : DrawElem,
	duration : f64,
	life : f64,
	update : proc(v: ^Vfx, delta: f64),
}

vfx_create :: proc(duration: f64, draw: DrawElem) -> Vfx {
	base :_VfxBase= {
		draw, duration, 0,
		proc(vfx: ^Vfx, delta: f64) {
			vfx.life += delta
		}
	}
	return { base, {} }
}

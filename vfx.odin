package main

Vfx :: struct {
	using __base : _VfxBase,
	__reserve : [128]u8,
}

_VfxBase :: struct {
	using draw_elem : DrawElem,
	die : bool,
	update : proc(v: ^Vfx, delta: f64),
}

vfx_create :: proc(update : proc(v: ^Vfx, delta: f64), draw: DrawElem) -> Vfx {
	return {
		{
			draw,
			false,
			update
		},
		{}
	}
}

package pool

import "core:math"

Pool :: struct($T:typeid) {
	available : [dynamic]T,
	capacity : int,
	using impl : ^PoolImpl(T),
}

PoolImpl :: struct($T:typeid) {
	_add : proc(v: ^T),
	_remove : proc(v: ^T)
}

init :: proc(p: ^Pool($T), cap: int, impl: ^PoolImpl(T)) {
	p.impl = impl
	p.available = make([dynamic]T, cap)
	_expand(p, cap)
}
release :: proc(p: ^Pool($T)) {
	assert(p.capacity == len(p.available), "Pool: All elements should be retired before you release the Pool.")
	for &e in p.available {
		p.impl._remove(&e)
	}
	delete(p.available)
}

get :: proc(p: ^Pool($T)) -> T {
	if len(p.available) == 0 {
		_expand(p, math.max(p.capacity, 1))
	}
	return pop(&p.available)
}
retire :: proc(p: ^Pool($T), v: T) {
	append(&p.available, v)
}

@private
_expand :: proc(p: ^Pool($T), inc: int) {
	for i in 0..<inc {
		append(&p.available, T{})
		p.impl._add(&p.available[len(p.available)-1])
	}
	p.capacity += inc
}

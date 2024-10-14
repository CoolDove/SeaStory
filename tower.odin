package main

Tower :: struct {
	pos : Position,
	level : int,
	target : ^Bird,
}

tower_update :: proc(tower: ^Tower, g: ^Game, delta: f64) {
}

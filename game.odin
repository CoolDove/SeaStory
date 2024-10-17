package main

import "base:runtime"
import "core:fmt"
import "core:time"
import "core:strconv"
import "core:slice"
import "core:math/rand"
import "core:math/noise"
import "core:math/linalg"
import "core:math"
import "core:log"
import "core:strings"
import hla "collections/hollow_array"
import pool "collections/pool"
import rl "vendor:raylib"

Game :: struct {
	block : [BLOCK_WIDTH*BLOCK_WIDTH]u32,
	mask : [BLOCK_WIDTH*BLOCK_WIDTH]u32,
	hitpoint : [BLOCK_WIDTH*BLOCK_WIDTH]int,
	mining : [BLOCK_WIDTH*BLOCK_WIDTH]int,
	sunken : [BLOCK_WIDTH*BLOCK_WIDTH]int, // 0: not sunken, -1: sunken, other: recovering
	buildingmap : [BLOCK_WIDTH*BLOCK_WIDTH]^Building,
	dead : bool,

	buildings : hla.HollowArray(^Building),
	birds : hla.HollowArray(Bird),

	land : [dynamic]Vec2i,
	birdgen : BirdGenerator,

	level : int,

	time : f64,

	// gameplay
	mineral : int,
	mine_interval : f64,
	mine_time : f64,
	mining_count : int, // update per second

	res : GameResources,

	birds_ai_buffer_pool : pool.Pool([dynamic]_BirdTargetCandidate),
	using operation : GameOperation,
}

BuildingPlacer :: struct {
	colddown : f64,
	colddown_time : f64,
	cost : int,
	name, key : cstring,
	building_type : typeid,
}

GameOperation :: struct {
	hover_cell : [2]int,
	last_position : rl.Vector2,
	mouse_position_drag_start : rl.Vector2,

	building_placers : map[typeid]BuildingPlacer,
	current_placer : ^BuildingPlacer,
	placeable : bool,
}
GameResources :: struct {
	tower_tex : rl.Texture,
	power_pump_tex : rl.Texture,
	no_power_tex : rl.Texture,
	minestation_tex : rl.Texture,
	mother_tex : rl.Texture,
	wind_off_tex : rl.Texture,
	wind_on_tex : rl.Texture,
	probe_tex : rl.Texture,

	bird_tex : rl.Texture,
	puffer_tex : rl.Texture,

	mask_slash : rl.Texture,

	select_sfx : rl.Sound,
	escape_sfx : rl.Sound,
	error_sfx : rl.Sound,
}

Position :: struct {
	x, y : int,
}

game_add_bird :: proc(g: ^Game, T: typeid, p: rl.Vector2) -> BirdHandle {
	b := hla.hla_append(&g.birds, Bird{})
	bird := hla.hla_get_pointer(b)
	bird_init(T, bird)
	bird.pos = p
	return b 
}

game_kill_bird :: proc(g: ^Game, b: hla.HollowArrayHandle(Bird)) {
	bird := hla.hla_get_pointer(b)
	bird->release()
	hla.hla_remove_handle(b)
}

sweep :: proc(using g: ^Game, x,y : int, peek:= false) -> bool/*alive*/ {
	idx := get_index(x,y)
	m := mask[idx]
	v := block[idx]
	if m == 0 {
		mask[idx] = FLAG_TOUCHED
		pos := Vec2i{x,y}
		append(&land, pos)
		mining[get_index(pos)] = count_minestations(pos)
		hitpoint[idx] = 20
		game.mineral += 2
		if v == 0 {
			_sweep :: proc(g: ^Game, x,y: int) {
				if in_range(x,y) {
					sweep(g, x,y, true)
				}
			}
			_sweep(g, x-1,y-1)
			_sweep(g, x,y-1)
			_sweep(g, x+1,y-1)
			_sweep(g, x-1,y)
			// _sweep(g, x,y)
			_sweep(g, x+1,y)
			_sweep(g, x-1,y+1)
			_sweep(g, x,y+1)
			_sweep(g, x+1,y+1)
		} else if v == ITEM_BOMB {
			return false
		}
	}
	return true
}

mark_toggle :: proc(using g: ^Game, x,y : int) {
	if !in_range(x,y) do return
	idx := get_index(x,y)
	if mask[idx] == 0 {
		mask[idx] = FLAG_MARKED
	} else if mask[idx] == FLAG_MARKED {
		mask[idx] = 0
	}
}

BirdsAiBufferPool :pool.PoolImpl([dynamic]_BirdTargetCandidate)= {
	_add = proc(v: ^[dynamic]_BirdTargetCandidate) {
		v^ = make([dynamic]_BirdTargetCandidate, 32)
	},
	_remove = proc(v: ^[dynamic]_BirdTargetCandidate) {
		delete(v^)
	},
}

game_init :: proc(g: ^Game) {
	pool.init(&g.birds_ai_buffer_pool, 0, &BirdsAiBufferPool)

	// generate map
	for i in 0..<160 do game.block[i] = ITEM_BOMB
	rand.reset(transmute(u64)time.tick_now())
	rand.shuffle(game.block[:])
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

	using game
	game.land = make([dynamic][2]int, 512)

	res.tower_tex = rl.LoadTexture("res/tower.png");
	res.power_pump_tex = rl.LoadTexture("res/power_pump.png");
	res.no_power_tex = rl.LoadTexture("res/no_power.png");
	res.minestation_tex = rl.LoadTexture("res/minestation.png");
	res.mother_tex = rl.LoadTexture("res/mother.png");
	res.mask_slash = rl.LoadTexture("res/mask_slash.png")
	res.wind_off_tex = rl.LoadTexture("res/wind_off.png")
	res.wind_on_tex = rl.LoadTexture("res/wind_on.png")
	res.probe_tex = rl.LoadTexture("res/probe.png")

	res.bird_tex = rl.LoadTexture("res/bird.png");
	res.puffer_tex = rl.LoadTexture("res/puffer.png");

	res.select_sfx = rl.LoadSound("res/select_sfx.mp3")
	res.escape_sfx = rl.LoadSound("res/escape_sfx.mp3")
	res.error_sfx = rl.LoadSound("res/error_sfx.mp3")

	mine_interval = 1

	buildings = hla.hla_make(^Building, 32)
	birds = hla.hla_make(Bird, 16)

	building_placers = make(map[typeid]BuildingPlacer)
	_register_building_placer(Tower, "炮塔", "Q")
	_register_building_placer(PowerPump, "能量泵", "W")
	_register_building_placer(Minestation, "采集站", "E")
	_register_building_placer(Wind, "风墙", "R")
	_register_building_placer(Probe, "探针", "A")

	_register_building_placer :: proc(t: typeid, name, key : cstring) {
		c := building_get_colddown(t)
		game.building_placers[t] = {
			c, c,
			building_get_cost(t),
			name, key,
			t
		}
	}

	{// sweep the first cell
		for i: int; true; i += 1 {
			p := cast(int)(BLOCK_WIDTH * BLOCK_WIDTH / 2) + cast(int)BLOCK_WIDTH/2 + (1 if i%2==0 else -1) * auto_cast i/2
			fmt.printf("try index: {} ({})\n", p, block[p])
			if block[p] == 0 {
				x, y := p%auto_cast BLOCK_WIDTH, p/auto_cast BLOCK_WIDTH
				sweep(&game, x, y)
				b := building_new_(Mother, {x,y})
				h := hla.hla_append(&g.buildings, b)
				building_init(b)
				buildingmap[get_index(x, y)] = b
				camera.target = b.center
				break
			}
		}
	}

	mineral = 500
}

game_release :: proc(using g: ^Game) {
	for b in hla.ites_alive_value(&g.buildings) {
		building_release(b)
		free(b)
	}
	hla.hla_delete(&g.buildings)
	for b in hla.ites_alive_handle(&g.birds) {
		game_kill_bird(g, b)
	}
	hla.hla_delete(&g.birds)
	delete(game.building_placers)
	delete(game.land)
	pool.release(&game.birds_ai_buffer_pool)

	rl.UnloadTexture(res.tower_tex)
	rl.UnloadTexture(res.power_pump_tex)
	rl.UnloadTexture(res.no_power_tex)
	rl.UnloadTexture(res.minestation_tex)
	rl.UnloadTexture(res.mother_tex)
	rl.UnloadTexture(res.mask_slash)
	rl.UnloadTexture(res.wind_off_tex)
	rl.UnloadTexture(res.wind_on_tex)
	rl.UnloadTexture(res.probe_tex)

	rl.UnloadTexture(res.bird_tex)
	rl.UnloadTexture(res.puffer_tex)

	rl.UnloadSound(res.select_sfx)
	rl.UnloadSound(res.escape_sfx)
	rl.UnloadSound(res.error_sfx)
}

_game_update_dead :: proc(delta: f64) {
	if rl.IsMouseButtonPressed(.LEFT) {
		game_end = true
	}
}

game_update :: proc(using g: ^Game, delta: f64) {
	if dead {
		_game_update_dead(delta)
		return
	}

	if GAME_DEBUG {
		if rl.IsKeyDown(.F2) {
			for _, &placer in game.building_placers {
				placer.colddown_time -= 1
				if placer.colddown_time < 0 do placer.colddown_time = 0
			}
		}
		if rl.IsKeyPressed(.F3) {
			if game.birds.count == 0 {
				if birdgen_is_working(&g.birdgen) {
					game.birdgen.wave.time = 0.1
				}
			} else {
				ite:int
				for b in hla.ite_alive_ptr(&game.birds, &ite) {
					b.hitpoint = 0
				}
			}
		}
	}

	hover_world_position := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)
	hover_cell = {cast(int)hover_world_position.x, cast(int)hover_world_position.y}

	dragged_distance := linalg.distance(mouse_position_drag_start, rl.GetMousePosition())

	// ** operation
	if rl.IsMouseButtonPressed(.MIDDLE) {
		last_position = rl.GetMousePosition()
		mouse_position_drag_start = last_position
	}
	if rl.IsMouseButtonDown(.MIDDLE) {
		last := rl.GetScreenToWorld2D(last_position, camera)
		now := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)
		camera.target += last-now
	} 

	if rl.IsKeyReleased(.ESCAPE) {
		game.current_placer = nil
		rl.PlaySound(res.escape_sfx)
	} else {
		if rl.IsKeyReleased(.Q) {
			game.current_placer = &game.building_placers[Tower]
			rl.PlaySound(res.select_sfx)
		} else if rl.IsKeyReleased(.W) {
			game.current_placer = &game.building_placers[PowerPump]
			rl.PlaySound(res.select_sfx)
		} else if rl.IsKeyReleased(.E) {
			game.current_placer = &game.building_placers[Minestation]
			rl.PlaySound(res.select_sfx)
		} else if rl.IsKeyReleased(.R) {
			game.current_placer = &game.building_placers[Wind]
			rl.PlaySound(res.select_sfx)
		} else if rl.IsKeyReleased(.A) {
			game.current_placer = &game.building_placers[Probe]
			rl.PlaySound(res.select_sfx)
		}
	}

	if in_range(hover_cell.x, hover_cell.y) && rl.IsKeyReleased(.X) {
		idx := get_index(hover_cell.x, hover_cell.y)
		building := game.buildingmap[idx]
		if building != nil do building.hitpoint -= 100
		else if mask[idx] == FLAG_TOUCHED && sunken[idx] == 0 {
			hitpoint[idx] -= 10
		}
	}

	placeable = false
	if game.current_placer != nil {
		p := game.current_placer
		is_water_place := _building_vtable(p.building_type)._is_place_on_water()
		idx := get_index(hover_cell.x, hover_cell.y)
		if in_range(hover_cell.x, hover_cell.y) {
			placeable = mask[idx] == FLAG_TOUCHED
			if is_water_place do placeable = !placeable
			placeable &= game.buildingmap[idx] == nil
			placeable &= building_placers[p.building_type].colddown_time <= 0
			placeable &= building_get_cost(p.building_type) <= game.mineral
			placeable &= game.sunken[idx] == 0
		}
	}

	if rl.IsMouseButtonReleased(.RIGHT) {// place building
		if current_placer != nil && placeable {
			b := building_new_(current_placer.building_type, hover_cell)
			h := hla.hla_append(&g.buildings, b)
			building_init(b)
			buildingmap[get_index(hover_cell.x, hover_cell.y)] = b
			game.mineral -= building_get_cost(current_placer.building_type);
			current_placer.colddown_time = current_placer.colddown // reset colddown
			rl.PlaySound(res.select_sfx)
		} else {
			mark_toggle(&game, hover_cell.x, hover_cell.y)
		}
	}

	if rl.IsMouseButtonReleased(.LEFT) {
		x, y:= hover_cell.x, hover_cell.y
		if in_range(x, y) && game.buildingmap[get_index(x, y)] == nil {
			// ** sweep
			if !sweep(&game, x, y) {
				rl.PlaySound(res.error_sfx)
				_blow_cell(hover_cell+{-1,-1})
				_blow_cell(hover_cell+{0,-1})
				_blow_cell(hover_cell+{1,-1})
				_blow_cell(hover_cell+{-1,0})
				_blow_cell(hover_cell+{0,0})
				_blow_cell(hover_cell+{1,0})
				_blow_cell(hover_cell+{-1,1})
				_blow_cell(hover_cell+{0,1})
				_blow_cell(hover_cell+{1,1})
				_blow_cell :: proc(p: Vec2i) {
					if !in_range(p) do return
					idx := get_index(p.x, p.y)
					building := game.buildingmap[get_index(p.x, p.y)]
					if building != nil do building.hitpoint = 0
					if game.mask[idx] != FLAG_TOUCHED {
						sweep(&game, p.x, p.y)
					}
					game.hitpoint[idx] = 0
				}
			}
		}
	}

	_is_double_button :: proc(btn, btp: rl.MouseButton) -> bool {
		return rl.IsMouseButtonPressed(btn) && rl.IsMouseButtonDown(btp)
	}
	if _is_double_button(.LEFT,.RIGHT) || _is_double_button(.RIGHT,.LEFT) {
	}

	zoom_speed_max, zoom_speed_min :f32= 1.2, 0.2
	zoom_max, zoom_min :f32= 56, 18
	zoom_speed :f32= ((camera.zoom-zoom_min)/(zoom_max-zoom_min)) * ( zoom_speed_max-zoom_speed_min ) + zoom_speed_min
	camera.zoom += rl.GetMouseWheelMove() * zoom_speed
	camera.zoom = clamp(camera.zoom, zoom_min, zoom_max)

	last_position = rl.GetMousePosition()

	// ** game logic
	for birdh in hla.ites_alive_handle(&game.birds) {// bird die
		bird := hla.hla_get_pointer(birdh)
		if bird.hitpoint <= 0 {
			bird->release()
			hla.hla_remove_handle(birdh)
		}
	}

	for bh in hla.ites_alive_handle(&game.buildings) {// building die
		b := hla.hla_get_value(bh)
		if b.hitpoint <= 0 {
			building_release(b)
			game.buildingmap[get_index(b.position.x, b.position.y)] = nil
			hla.hla_remove_handle(bh)
			free(b)
		}
	}

	for i := len(game.land)-1; i>-1; i-=1 {// land die
		landp := game.land[i]
		idx := get_index(landp.x, landp.y)
		if hitpoint[idx] <= 0 {
			ordered_remove(&game.land, i)
			game.sunken[idx] = -1
			game.mining[idx] = 0
		}
	}

	// ** mining
	if mine_time >= mine_interval {
		mining_count = 0
		for i in land {
			if mining[get_index(i.x,i.y)] > 0 do mining_count += 1
		}
		mineral += 1+mining_count / 10
		mine_time = 0
	} else {
		mine_time += delta
	}


	// bird gen
	if game.birds.count == 0 && !birdgen_is_working(&g.birdgen) {
		birdgen_set(&g.birdgen, enemy_config[math.min(len(enemy_config)-1, level)])
		game.level += 1
	}
	birdgen_update(g, &g.birdgen, 1.0/60.0)

	for building_handle in hla.ites_alive_handle(&game.buildings) {
		building := hla.hla_get_pointer(building_handle)^
		building.update(transmute(hla._HollowArrayHandle)building_handle, delta)
	}

	for bird in hla.ites_alive_ptr(&g.birds) {
		bird->update(delta)
	}

	for t, &p in game.building_placers {
		if p.colddown_time > 0 {
			p.colddown_time -= delta
		} else {
			p.colddown_time = 0
		}
	}
	g.time += delta
}

game_draw :: proc(using g: ^Game) {
	for x in 0..<BLOCK_WIDTH {
		for y in 0..<BLOCK_WIDTH {
			pos := rl.Vector2{cast(f32)x,cast(f32)y}
			n := noise.noise_2d(42, noise.Vec2{cast(f64)x,cast(f64)y}+0.6*{time, time})
			m := mask[get_index(cast(int)x,cast(int)y)]
			if m == FLAG_TOUCHED {
				points : [4]rl.Vector2
				points[0] = pos + {0.1, 0.1}
				points[1] = pos + {1.1, 0.1}
				points[2] = pos + {1.1, 1.1}
				points[3] = pos + {0.1, 1.1}
				for i in 0..<4 {
					p := points[i]
					points[i] = p + 0.04 * noise.noise_2d(42, noise.Vec2{cast(f64)p.x,cast(f64)p.y}+0.6*{time, time})
				}
				rl.DrawTriangle( points[0], points[2], points[1] , {0,0,0, 64})
				rl.DrawTriangle( points[0], points[3], points[2] , {0,0,0, 64})
			}
		}
	}

	for x in 0..<BLOCK_WIDTH {
		for y in 0..<BLOCK_WIDTH {
			draw_cell(g, auto_cast x, auto_cast y)
		}
	}

	rl.DrawLine(-100, 0, 100, 0, rl.Color{255,255,0, 255})
	rl.DrawLine(0, -100, 0, 100, rl.Color{0,255,0, 255})

	// draw cursor
	if in_range(hover_cell.x, hover_cell.y) {
		hover_cell_corner := Vec2{cast(f32)hover_cell.x, cast(f32)hover_cell.y}
		rl.DrawRectangleV(hover_cell_corner, {1,1}, {255,255,255, 80})
		if placeable do rl.DrawCircleV(hover_cell_corner+{0.5,0.5}, 0.4, {20, 240, 20, 90})
	}

	draw_elems := make([dynamic]DrawElem); defer delete(draw_elems)

	// draw birds
	for bird in hla.ites_alive_ptr(&g.birds) {
		append(&draw_elems, bird_get_draw_elem(bird))
	}

	for building_handle in hla.ites_alive_handle(&game.buildings) {
		handle := new(hla._HollowArrayHandle)
		handle^ = transmute(hla._HollowArrayHandle)building_handle
		if building, ok := hla.hla_get_value(building_handle); ok {
			append(&draw_elems, DrawElem{
				handle,
				auto_cast building.position.y,
				proc(handle: rawptr) {
					using hla
					handleptr := cast(^HollowArrayHandle(^Building))handle
					if building, ok := hla_get_value(handleptr^); ok {
						building.pre_draw(transmute(hla._HollowArrayHandle)handleptr^)
					}
				},
				proc(handle: rawptr) {
					using hla
					handleptr := cast(^HollowArrayHandle(^Building))handle
					building := hla_get_value(handleptr^)
					if building, ok := hla_get_value(handleptr^); ok {
						building.draw(transmute(hla._HollowArrayHandle)handleptr^)
					}
				},
				proc(handle: rawptr) {
					using hla
					handleptr := cast(^HollowArrayHandle(^Building))handle
					if building, ok := hla_get_value(handleptr^); ok {
						building.extra_draw(transmute(hla._HollowArrayHandle)handleptr^)
					}
				},
				proc(handle: rawptr) {
					using hla
					handleptr := cast(^hla._HollowArrayHandle)handle
					free(handleptr)
				}
			})
		}
	}

	slice.sort_by_cmp(draw_elems[:], proc(a, b: DrawElem) -> slice.Ordering {
		if a.order > b.order do return .Greater
		else if a.order < b.order do return .Less
		else do return .Equal
	})

	for e in draw_elems {
		e.pre_draw(e.data)
	}
	for e in draw_elems {
		e.draw(e.data)
	}
	for e in draw_elems {
		e.extra_draw(e.data)
	}
	for e in draw_elems {
		e.free(e.data)
	}

	birdgen_draw(&game.birdgen)

	draw_cell :: proc(using g: ^Game, x,y: int) {
		idx := get_index(x,y)
		v,m := block[idx], mask[idx]
		pos :rl.Vector2= {cast(f32)x,cast(f32)y}
		if m == 0 {
			rl.DrawRectangleLinesEx(rl.Rectangle{pos.x, pos.y, 1,1}, 0.1, {0,60,155, 32})
		} else if m == FLAG_MARKED {
			rl.DrawRectangleLinesEx(rl.Rectangle{pos.x, pos.y, 1,1}, 0.1, {0,60,155, 32})
			// draw flag
			triangle := [3]rl.Vector2{ {0,0}, {0,0.4}, {0.4,0.2} }
			offset := rl.Vector2{0.3, 0.1}
			for &p in triangle do p += offset + pos

			// shadow
			soffset := rl.Vector2{0.03,0.03}
			rl.DrawTriangle(triangle[0]+soffset, triangle[1]+soffset, triangle[2]+soffset, {0,0,0,100})
			rl.DrawRectangleV(pos+offset+soffset, {0.08, 0.7}, {0,0,0,100})

			rl.DrawTriangle(triangle[0], triangle[1], triangle[2], {230,20,10,255})
			rl.DrawRectangleV(pos+offset, {0.08, 0.7}, {60,50,20, 255})
		} else if m == FLAG_TOUCHED {
			if v == ITEM_BOMB {
				rl.DrawCircleV(pos+{0.5,0.5}, 0.3, {200, 70, 40, 200})
			} else if v == ITEM_QUESTION {
				rl.DrawRectangleV(pos, {1,1}, {217, 160, 102, 255})
				if v != 0 {
					rl.DrawTextEx(rl.GetFontDefault(), "?",
						pos+{0.2, 0.1}, 0.8, 1, rl.Color{200, 190, 40, 200})
				}
			} else {
				// draw land
				rl.DrawRectangleV(pos, {1,1}, {217, 160, 102, 255})
				if v != 0 {
					rl.DrawTextEx(rl.GetFontDefault(), fmt.ctprintf("{}", v),
						pos+{0.2, 0.1}, 0.8, 1, rl.Color{200, 140, 85, 200})
				}
			}
			if game.sunken[idx] == -1 { // sunken mask
				// rl.DrawRectangleV(pos, {1,1}, {20, 90, 180, 128})
				rl.DrawTexturePro(res.mask_slash, {0,0,32,32}, {pos.x,pos.y,1,1}, {0,0}, 0, {20, 90, 180, 64})
			}
		}

		if (rl.IsKeyDown(.LEFT_ALT) || GAME_DEBUG) && mask[idx] == FLAG_TOUCHED && mining[idx]>0 {
			rl.DrawCircleV(pos+{0.5,0.5}, auto_cast(0.05 * math.abs(math.sin(game.time*2)) + 0.1), {40,60,180, 80})
		}
	}
}

draw_ui :: proc() {
	viewport := Vec2{cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()}

	card_width :f32= 50
	card_height :f32= 60

	rect :rl.Rectangle= { 10, viewport.y - card_height - 10, card_width, card_height }

	draw_mode_card(&game.building_placers[Tower], &rect)
	draw_mode_card(&game.building_placers[PowerPump], &rect)
	draw_mode_card(&game.building_placers[Minestation], &rect)
	draw_mode_card(&game.building_placers[Wind], &rect)
	rect.x += 15
	draw_mode_card(&game.building_placers[Probe], &rect)

	str_mineral := fmt.ctprintf("矿:{} (+{}/s) 地块:{}/{}", game.mineral, 1+game.mining_count/10, game.mining_count, len(game.land))
	rl.DrawTextEx(FONT_DEFAULT, str_mineral, {10, viewport.y - card_height - 50} + {2,2}, 28, 1, {0,0,0, 64})
	rl.DrawTextEx(FONT_DEFAULT, str_mineral, {10, viewport.y - card_height - 50}, 28, 1, rl.YELLOW)

	if game.birdgen.wave.time > 0 {
		str_enemy := fmt.ctprintf("第{}波敌袭: {:.1f} 秒后出现\n", game.level, game.birdgen.wave.time)
		rl.DrawTextEx(FONT_DEFAULT, str_enemy, {10, 80}, 42, 1, {200,30,30, 128})
	} else {
		str_enemy := fmt.ctprintf("第{}波敌袭中\n", game.level)
		rl.DrawTextEx(FONT_DEFAULT, str_enemy, {10, 80}, 42, 1, {200,30,30, 128})
	}

	draw_mode_card :: proc(using placer: ^BuildingPlacer, rect: ^rl.Rectangle) {
		shadow_rect := rect^
		shadow_rect.x += 8
		shadow_rect.y += 8
		selected := game.current_placer == placer
		rl.DrawRectangleRec(shadow_rect, {0,0,0, 64})
		if selected {;
			framer := rect^
			framer.x -= 4
			framer.y -= 4
			framer.width += 8
			framer.height += 8
			rl.DrawRectangleRec(framer, {40, 20, 40, 200})
		}
		rl.DrawRectangleRec(rect^, {200,200,200, 255})

		measure := rl.MeasureTextEx(FONT_DEFAULT, name, 20, 1)

		is_water_place := _building_vtable(building_type)._is_place_on_water()
		rl.DrawTextEx(FONT_DEFAULT, name, {rect.x+0.5*rect.width-0.5*measure.x, rect.y} + {0, measure.y - 20}, 20, 1, rl.BLUE if is_water_place else rl.BLACK)

		measure = rl.MeasureTextEx(FONT_DEFAULT, key, 20, 1)
		rl.DrawTextEx(FONT_DEFAULT, key, {rect.x+rect.width-measure.x, rect.y + rect.height - 20}, 20, 1, rl.GRAY)

		if transmute(int)building_type != 0 {
			cost := building_get_cost(building_type)
			color := rl.GREEN if cost <= game.mineral else rl.RED
			str := fmt.ctprintf("{}", cost)
			position :Vec2= {rect.x, rect.y + rect.width - 20}
			rl.DrawTextEx(FONT_DEFAULT, str, position, 20, 1, color)
		}

		colddown_rect := rect^
		colddown_rect.height *= cast(f32)(colddown_time/ colddown);
		rl.DrawRectangleRec(colddown_rect, {0,0,0, 64})

		rect.x += rect.width + 10
	}
	// draw dead
	if game.dead {
		rl.DrawTextEx(FONT_DEFAULT, "You lose, press mouse left to close game", {40, 140}, 48, 0, rl.BLACK)
	}

}

DrawElem :: struct {
	data : rawptr,
	order : f64,
	pre_draw : proc(data: rawptr),
	draw : proc(data: rawptr),
	extra_draw : proc(data: rawptr),
	free : proc(data: rawptr)
}

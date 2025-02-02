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
import tw "tween"

Game :: struct {
	block : [BLOCK_WIDTH*BLOCK_WIDTH]u32,
	mask : [BLOCK_WIDTH*BLOCK_WIDTH]u32,
	hitpoint : [BLOCK_WIDTH*BLOCK_WIDTH]int,
	mining : [BLOCK_WIDTH*BLOCK_WIDTH]int,
	sunken : [BLOCK_WIDTH*BLOCK_WIDTH]int, // 0: not sunken, -1: sunken, other: recovering
	buildingmap : [BLOCK_WIDTH*BLOCK_WIDTH]^Building,
	dead : bool,
	current_seed : u64,

	buildings : hla.HollowArray(^Building),
	birds : hla.HollowArray(Bird),

	land : [dynamic]Vec2i,
	birdgen : BirdGenerator,

	level : int,

	time : f64,

	tweener : tw.Tweener,

	vfx : hla.HollowArray(Vfx),

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
	description : cstring,
}

GameOperation :: struct {
	hover_cell : [2]int,
	hover_idx : int,
	last_position : rl.Vector2,
	mouse_position_drag_start : rl.Vector2,

	mousein_ui : bool,

	building_placers : map[typeid]BuildingPlacer,
	current_placer : ^BuildingPlacer,
	placeable : bool,

	remove_building_timer : f64,
	remove_building_holdtime : f64,

	hover_text : cstring,
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
	fog_tower_tex : rl.Texture,
	cannon_tower_tex : rl.Texture,

	bird_tex : rl.Texture,
	puffer_tex : rl.Texture,

	mask_slash : rl.Texture,

	select_sfx : rl.Sound,
	escape_sfx : rl.Sound,
	error_sfx : rl.Sound,

	shader_wave_grid : rl.Shader,
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
		if v == 0 {
			game.mineral += 2
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

count_around :: proc(pos: Vec2i) -> u32 {
	check :: proc(count: ^int, x,y: int) {
		if in_range(x,y) && game.block[get_index(x,y)] == ITEM_BOMB {
			count ^= count^ + 1
		}
	}
	x, y :int= auto_cast pos.x, auto_cast pos.y

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
	return auto_cast count
}

game_init :: proc(g: ^Game) {
	pool.init(&g.birds_ai_buffer_pool, 0, &BirdsAiBufferPool)

	// generate map
	for i in 0..<160 do game.block[i] = ITEM_BOMB
	game.current_seed = cast(u64)rand.int31()%9999
	rand.reset(game.current_seed)
	rand.shuffle(game.block[:])
	for x in 0..<BLOCK_WIDTH {
		for y in 0..<BLOCK_WIDTH {
			using game
			x, y :int= auto_cast x, auto_cast y
			if block[get_index(x,y)] == ITEM_BOMB do continue
			count := count_around({x,y})
			block[get_index(x,y)] = count
			if count > 0 && rand.float32() < 0.2 {
				block[get_index(x,y)] = ITEM_QUESTION
			}
		}
	}

	using game
	game.land = make([dynamic][2]int, 512)

	load_resource(&res)

	remove_building_holdtime = 1
	mine_interval = 1

	buildings = hla.hla_make(^Building, 32)
	birds = hla.hla_make(Bird, 16)
	vfx = hla.hla_make(Vfx, 16)

	building_placers = make(map[typeid]BuildingPlacer)
	_register_building_placer(CannonTower, "炮塔", "Q", "缓慢发射炮弹攻击")
	_register_building_placer(Tower, "激光塔", "W", "使用激光攻击单个敌人，持续攻击会使威力提升")
	_register_building_placer(FogTower, "驱雾塔", "E", "发出振荡波攻击范围内的所有敌人，同时驱散迷雾")
	_register_building_placer(Wind, "风墙", "R", "使经过的敌人减速")
	_register_building_placer(Probe, "探针", "A", "[需要水面]探测水下的能源并自动标记")
	_register_building_placer(PowerPump, "能量泵", "S", "[需要能源]通过水下的能源将能量辐射到范围内的其它建筑")
	_register_building_placer(Minestation, "采集站", "D", "[需要能源]通过范围内的地块采集矿物")

	p := &game.building_placers[Probe]
	p.colddown_time = 0

	_register_building_placer :: proc(t: typeid, name, key, desc : cstring) {
		c := building_get_colddown(t)
		game.building_placers[t] = {
			c, c,
			building_get_cost(t),
			name, key,
			t,
			desc
		}
	}

	{// sweep the first cell
		ite:Vec3i
		for c in ite_around({auto_cast BLOCK_WIDTH/2, auto_cast BLOCK_WIDTH/2}, auto_cast BLOCK_WIDTH/2, &ite) {
			if in_range(c) && block[get_index(c)] == 0 {
				x, y := c.x, c.y
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

	tw.tweener_init(&tweener, 16)

	mineral = 420
}

game_release :: proc(using g: ^Game) {
	tw.tweener_release(&tweener)
	birdgen_release(&game.birdgen)

	for b in hla.ites_alive_value(&g.buildings) {
		building_release(b)
		free(b)
	}
	hla.hla_delete(&g.buildings)
	for b in hla.ites_alive_handle(&g.birds) {
		game_kill_bird(g, b)
	}
	hla.hla_delete(&g.birds)

	hla.hla_delete(&g.vfx)

	delete(game.building_placers)
	delete(game.land)
	pool.release(&game.birds_ai_buffer_pool)

	unload_resource(&res)
}

_game_update_dead :: proc(delta: f64) {
	if rl.IsMouseButtonPressed(.LEFT) {
		// game_end = true
	}
}

cell_can_repair :: proc(p: Vec2i) -> bool {
	using game
	idx := get_index(p)
	return in_range(p.x, p.y) && sunken[idx] == -1 && block[idx] != ITEM_BOMB
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
		if rl.IsKeyPressed(.F4) {
			game.mineral += 100
		}
	}

	hover_world_position := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)
	hover_cell = {cast(int)hover_world_position.x, cast(int)hover_world_position.y}
	hover_idx = get_index(hover_cell)

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
			game.current_placer = &game.building_placers[CannonTower]
			rl.PlaySound(res.select_sfx)
		} else if rl.IsKeyReleased(.W) {
			game.current_placer = &game.building_placers[Tower]
			rl.PlaySound(res.select_sfx)
		} else if rl.IsKeyReleased(.E) {
			game.current_placer = &game.building_placers[FogTower]
			rl.PlaySound(res.select_sfx)
		} else if rl.IsKeyReleased(.R) {
			game.current_placer = &game.building_placers[Wind]
			rl.PlaySound(res.select_sfx)
		} else if rl.IsKeyReleased(.A) {
			game.current_placer = &game.building_placers[Probe]
			rl.PlaySound(res.select_sfx)
		} else if rl.IsKeyReleased(.S) {
			game.current_placer = &game.building_placers[PowerPump]
			rl.PlaySound(res.select_sfx)
		} else if rl.IsKeyReleased(.D) {
			game.current_placer = &game.building_placers[Minestation]
			rl.PlaySound(res.select_sfx)
		}
	}

	// land repair
	if cell_can_repair(hover_cell) {
		if rl.IsKeyPressed(.X) && mineral > 50 {
			sunken[hover_idx] = 0
			mineral -= 50
		}
	}

	// building remove
	if in_range(hover_cell.x, hover_cell.y) && buildingmap[get_index(hover_cell)] != nil {
		hover_building := buildingmap[get_index(hover_cell)]
		if rl.IsKeyPressed(.X) {
			remove_building_timer += delta
		} else if rl.IsKeyDown(.X) {
			if remove_building_timer > 0 {
				remove_building_timer += delta
				remove_building_timer = math.min(remove_building_timer, remove_building_holdtime)
			}
		} else if rl.IsKeyReleased(.X) && remove_building_timer >= remove_building_holdtime {
			if hover_building != nil {
				m := get_building_remove_return(hover_building)
				mineral += m
				hover_building.hitpoint = 0
				vfx_number(hover_building.center, m, rl.YELLOW)
			}
		} else {
			remove_building_timer = 0.0
		}
	} else {
		remove_building_timer = 0.0
	}

	if in_range(hover_cell.x, hover_cell.y) && rl.IsKeyDown(.LEFT_ALT) && rl.IsKeyReleased(.X) {
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

	if !mousein_ui && rl.IsMouseButtonReleased(.RIGHT) {// place building
		if current_placer != nil do game.current_placer = nil
		else do mark_toggle(&game, hover_cell.x, hover_cell.y)
	}

	if !mousein_ui && rl.IsMouseButtonReleased(.LEFT) {
		if current_placer != nil {// ** place building
			if placeable {
				b := building_new_(current_placer.building_type, hover_cell)
				h := hla.hla_append(&g.buildings, b)
				building_init(b)
				buildingmap[get_index(hover_cell.x, hover_cell.y)] = b
				game.mineral -= building_get_cost(current_placer.building_type);
				current_placer.colddown_time = current_placer.colddown // reset colddown
				rl.PlaySound(res.select_sfx)
				game.current_placer = nil
			}
		} else {// ** sweep cell
			x, y:= hover_cell.x, hover_cell.y
			if in_range(x, y) && game.buildingmap[get_index(x, y)] == nil {
				// ** sweep
				if !sweep(&game, x, y) {
					rl.PlaySound(res.error_sfx)
					center := get_center(hover_cell)
					vfx_boom(center, 1.35, 0.6)
					for b in hla.ites_alive_ptr(&game.birds) {
						dist := linalg.distance(b.pos+{0.5,0.5}, center)
						if dist < 1.8 {
							dmg := math.min(b.hitpoint, 200)
							b.hitpoint -= dmg
							vfx_number(b.pos, dmg, PLAYER_ATK_COLOR)
						}
					}
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


	tw.tweener_update(&game.tweener, cast(f32)delta)

	for _vfx in hla.ites_alive_ptr(&g.vfx) {
		_vfx->update(delta)
	}

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

	ite:int
	for vfx, handle in hla.ite_alive_ptr_handle(&game.vfx, &ite) {
		if vfx.life >= vfx.duration {
			hla.hla_remove_handle(handle)
		}
	}

	// ** mining
	if mine_time >= mine_interval {
		mining_count = 0
		for i in land {
			if mining[get_index(i.x,i.y)] > 0 do mining_count += 1
		}
		mineral += 1+ mining_count / 8
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

	for building in hla.ites_alive_value(&game.buildings) {
		building->update(delta)
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

	hover_text = get_hover_text()


	g.time += delta
}

get_hover_text :: proc() -> cstring {
	using game
	hover_building := buildingmap[hover_idx] if in_range(hover_cell) else nil
	if current_placer != nil {
		if _building_vtable(current_placer.building_type)._is_place_on_water() {
			if mask[hover_idx] != FLAG_TOUCHED {
				return "[左键]放置，[右键/Esc]取消"
			} else {
				return "这个建筑只能放在有[能源(雷)]的水面上, [左键]放置，[右键/Esc]取消"
			}
		} else {
			return "[左键]放置，[右键/Esc]取消"
		}
	} else if cell_can_repair(hover_cell) {
		return "按[X]花费50矿修复地块"
	} else if remove_building_timer > 0 {
		return fmt.ctprintf("拆除中{:.2f}%%", 100 * (remove_building_timer/remove_building_holdtime))
	} else if hover_building != nil {
		if hover_building.hitpoint < hover_building.hitpoint_define/2 {
			if hover_building.type == Mother {
				return "主城会在不受攻击时缓慢恢复"
			} else {
				return fmt.ctprintf("长按[X]拆除建筑可返还{}点矿石", get_building_remove_return(hover_building))
			}
		} else {
			if hover_building.powered == 0 {
				return "没电啊，给我建个[能源泵]吧"
			}
		}
	}
	return ""
}

get_building_remove_return :: proc(b: ^Building) -> int {
	t := cast(f64)b.hitpoint/cast(f64)b.hitpoint_define
	cost := cast(f64)building_get_cost(b.type)
	return cast(int)(0.8 * t*cost)
}

game_draw :: proc(using g: ^Game) {
	rl.BeginShaderMode(res.shader_wave_grid) 
	{
		// @TEMPORARY
		{
			loc := rl.GetShaderLocation(res.shader_wave_grid, "_time")
			time :f32= auto_cast game.time
			rl.SetShaderValue(res.shader_wave_grid, loc, &time, .FLOAT)
		}
		{
			mat_camera := rl.GetCameraMatrix2D(camera)
			loc := rl.GetShaderLocation(res.shader_wave_grid, "_matCamera")
			rl.SetShaderValueMatrix(res.shader_wave_grid, loc, mat_camera)
		}
		// draw wave grid
		for x in 0..<BLOCK_WIDTH {
			for y in 0..<BLOCK_WIDTH {
				rl.DrawRectangleLinesEx(rl.Rectangle{auto_cast x, auto_cast y, 1,1}, 0.1, {0,60,155, 32})
				m := mask[get_index(cast(int)x,cast(int)y)]
				if m == FLAG_TOUCHED {
					rl.DrawRectangleV({auto_cast x, auto_cast y}+{0.1,0.1}, {1,1}, {0,0,0, 64})
				}
			}
		}
		rl.EndShaderMode()
	}
	for x in 0..<BLOCK_WIDTH {
		for y in 0..<BLOCK_WIDTH {
			draw_cell(g, auto_cast x, auto_cast y)
		}
	}

	// draw cursor
	if !mousein_ui && in_range(hover_cell.x, hover_cell.y) {
		hover_cell_corner := Vec2{cast(f32)hover_cell.x, cast(f32)hover_cell.y}
		rl.DrawRectangleV(hover_cell_corner, {1,1}, {255,255,255, 80})

		if placeable do rl.DrawCircleV(hover_cell_corner+{0.5,0.5}, 0.4, {20, 240, 20, 90})
		else if current_placer != nil {
			p :Vec2= {cast(f32)hover_cell.x, cast(f32)hover_cell.y}
			rl.DrawLineEx(p+{.1,.1}, p+{.8,.8}, 0.3, {230, 40, 40, 120})
			rl.DrawLineEx(p+{.8,.1}, p+{.1,.8}, 0.3, {230, 40, 40, 120})
		}

		if placeable && current_placer != nil {
			vtable := _building_vtable(current_placer.building_type)
			if vtable.preview_draw != nil {
				vtable.preview_draw(hover_cell)
			}
		}
	}

	draw_elems := make([dynamic]DrawElem); defer delete(draw_elems)

	// draw vfxs
	for vfx in hla.ites_alive_ptr(&g.vfx) {
		e := (cast(^DrawElem)vfx)^
		e.data = vfx
		append(&draw_elems, e)
	}

	// draw birds
	for bird in hla.ites_alive_ptr(&g.birds) {
		append(&draw_elems, bird_get_draw_elem(bird))
	}

	for building in hla.ites_alive_value(&game.buildings) {
		append(&draw_elems, DrawElem{
			building,
			auto_cast building.position.y,
			proc(building: rawptr) {
				building := cast(^Building)building
				building->pre_draw()
			},
			proc(building: rawptr) {
				building := cast(^Building)building
				building->draw()
			},
			proc(building: rawptr) {
				building := cast(^Building)building
				building->extra_draw()
			},
			proc(building: rawptr) {
			}
		})
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
		} else if m == FLAG_MARKED {
			// rl.DrawRectangleLinesEx(rl.Rectangle{pos.x, pos.y, 1,1}, 0.1, {0,60,155, 32})
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
				rl.DrawTexturePro(res.mask_slash, {0,0,32,32}, {pos.x,pos.y,1,1}, {0,0}, 0, {20, 90, 180, 64})
			}
		}

		if (rl.IsKeyDown(.LEFT_ALT) || GAME_DEBUG) && mask[idx] == FLAG_TOUCHED && mining[idx]>0 {
			rl.DrawCircleV(pos+{0.5,0.5}, auto_cast(0.05 * math.abs(math.sin(game.time*2)) + 0.1), {40,60,180, 80})
		}
	}
}


is_in_rect :: proc(p: Vec2, r: rl.Rectangle) -> bool {
	return !(p.x < r.x || p.x > r.x + r.width || p.y < r.y || p.y > r.y+r.height)
}

draw_ui :: proc() {
	viewport := Vec2{cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()}

	card_width :f32= 50
	card_height :f32= 60

	rect :rl.Rectangle= { 0, viewport.y - card_height - 25, card_width, card_height }
	rect.x = (viewport.x - 7*60) * 0.5

	mousein := false

	bgrect :rl.Rectangle= {rect.x - 10, viewport.y-card_height-100, 7*60+25, 150}
	rl.DrawRectangleRec(bgrect, {0,0,0, 64})
	mousein |= is_in_rect(rl.GetMousePosition(), bgrect)

	mousein |= draw_mode_card(&game.building_placers[CannonTower], &rect)
	mousein |= draw_mode_card(&game.building_placers[Tower], &rect)
	mousein |= draw_mode_card(&game.building_placers[FogTower], &rect)
	mousein |= draw_mode_card(&game.building_placers[Wind], &rect)
	rect.x += 15
	mousein |= draw_mode_card(&game.building_placers[Probe], &rect)
	mousein |= draw_mode_card(&game.building_placers[PowerPump], &rect)
	mousein |= draw_mode_card(&game.building_placers[Minestation], &rect)

	game.mousein_ui = mousein

	{
		str_mineral := fmt.ctprintf("矿:{} (+{}/s) \t地块:{}/{}", game.mineral, 1+game.mining_count/10, game.mining_count, len(game.land))
		size :f32= 28
		measure := rl.MeasureTextEx(FONT_DEFAULT, str_mineral, size, 1)
		pos :Vec2= {(viewport.x-measure.x)*0.5, viewport.y - card_height - 90}
		rl.DrawTextEx(FONT_DEFAULT, str_mineral, pos + {2,2}, size, 1, {0,0,0, 64})
		rl.DrawTextEx(FONT_DEFAULT, str_mineral, pos, size, 1, rl.YELLOW)
	}

	if game.birdgen.wave.time > 0 {
		str_enemy := fmt.ctprintf("第{}波敌袭: {:.1f} 秒后出现\n", game.level, game.birdgen.wave.time)
		rl.DrawTextEx(FONT_DEFAULT, str_enemy, {10, 80}, 42, 1, {200,30,30, 128})
	} else {
		str_enemy := fmt.ctprintf("第{}波敌袭中\n", game.level)
		rl.DrawTextEx(FONT_DEFAULT, str_enemy, {10, 80}, 42, 1, {200,30,30, 128})
	}

	draw_mode_card :: proc(using placer: ^BuildingPlacer, rect: ^rl.Rectangle) -> bool /*mouse in*/{
		mpos := rl.GetMousePosition()
		mousein := !(mpos.x < rect.x || mpos.x > rect.x + rect.width || mpos.y < rect.y || mpos.y > rect.y+rect.height)
		if mousein {
			if rl.IsMouseButtonPressed(.LEFT) {
				game.current_placer = &game.building_placers[placer.building_type]
				rl.PlaySound(game.res.select_sfx)
			}
		}
		// ---
		shadow_rect := rect^
		shadow_rect.x += 4
		shadow_rect.y += 4
		selected := game.current_placer == placer
		rl.DrawRectangleRec(shadow_rect, {0,0,0, 64})
		if selected {;
			framer := rect^
			framer.x -= 4
			framer.y -= 4
			framer.width += 8
			framer.height += 8
			rl.DrawRectangleRec(framer, {230, 220, 40, 200})
		}
		rl.DrawRectangleRec(rect^, {200,200,200, 255})

		measure := rl.MeasureTextEx(FONT_DEFAULT, name, 20, 1)

		is_water_place := _building_vtable(building_type)._is_place_on_water()
		rl.DrawTextEx(FONT_DEFAULT, name, {rect.x+0.5*rect.width-0.5*measure.x, rect.y} + {0, measure.y - 20}, 20, 1, rl.BLUE if is_water_place else rl.BLACK)

		measure = rl.MeasureTextEx(FONT_DEFAULT, key, 20, 1)
		rl.DrawTextEx(FONT_DEFAULT, key, {rect.x+rect.width-measure.x-4, rect.y + rect.height - 20}, 20, 1, rl.GRAY)

		if transmute(int)building_type != 0 {
			cost := building_get_cost(building_type)
			color := rl.Color{10, 200, 20, 255} if cost <= game.mineral else rl.RED
			str := fmt.ctprintf("{}", cost)
			position :Vec2= {rect.x+5, rect.y + rect.width - 20}
			size :f32= 24
			rl.DrawTextEx(FONT_DEFAULT, str, position+{1,1}, size, 1, rl.BLACK)
			rl.DrawTextEx(FONT_DEFAULT, str, position+{-1,1}, size, 1, rl.BLACK)
			rl.DrawTextEx(FONT_DEFAULT, str, position+{1,-1}, size, 1, rl.BLACK)
			rl.DrawTextEx(FONT_DEFAULT, str, position+{-1,-1}, size, 1, rl.BLACK)
			rl.DrawTextEx(FONT_DEFAULT, str, position, size, 1, color)
		}

		colddown_rect := rect^
		colddown_rect.height *= cast(f32)(colddown_time/ colddown);
		rl.DrawRectangleRec(colddown_rect, {0,0,0, 64})

		rect.x += rect.width + 10
		return mousein
	}

	{
		pos := rl.GetMousePosition() + {6,6}
		size :f32= 24
		measure := rl.MeasureTextEx(FONT_DEFAULT, game.hover_text, size, 0)
		rl.DrawRectangleV(pos, measure, {0,0,0, 128})
		rl.DrawTextEx(FONT_DEFAULT, game.hover_text, pos, size, 0, {240,240,240, 240})
	}
	{
		rl.DrawTextEx(FONT_DEFAULT, "Shift - 查看火力覆盖情况", {10, viewport.y-80}, 26, 0, {100, 100, 100, 230})
		rl.DrawTextEx(FONT_DEFAULT, "Alt - 查看电力，采矿情况", {10, viewport.y-50}, 26, 0, {100, 100, 100, 230})
	}

	{
		msg :cstring= "自由模式，[鼠标左键]开启地块，[鼠标右键]标记"
		if game.current_placer != nil do msg = fmt.ctprintf("{} - {}", game.current_placer.name, game.current_placer.description)
		size :f32= 28
		measure := rl.MeasureTextEx(FONT_DEFAULT, msg, size, 0)
		w, h := cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()
		pos :Vec2= {(w-measure.x)*0.5, h-120}
		rl.DrawTextEx(FONT_DEFAULT, msg, pos+{2,2}, size, 0, {0,0,0, 64})
		rl.DrawTextEx(FONT_DEFAULT, msg, pos, size, 0, {230, 210, 190, 255})
	}

	// draw dead
	if game.dead {
		msg := fmt.ctprintf("游戏结束，你坚守了{}波攻击", game.level)
		measure := rl.MeasureTextEx(FONT_DEFAULT, msg, 48, 0)
		w, h := cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()
		pos :Vec2= {(w-measure.x)*0.5, (h-measure.y)*0.5}
		rl.DrawRectangle(0,0, cast(i32)w, cast(i32)h, {0,0,0, 64})
		rl.DrawTextEx(FONT_DEFAULT, msg, pos+{2,2}, 48, 0, {0,0,0, 64})
		rl.DrawTextEx(FONT_DEFAULT, msg, pos, 48, 0, rl.ORANGE)
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
_DrawElem_Empty :DrawElem= {
	data = nil,
	order = 0,
	pre_draw = proc(data: rawptr) {},
	draw = proc(data: rawptr) {},
	extra_draw = proc(data: rawptr) {},
	free = proc(data: rawptr) {},
}

epre_draw :: proc(data: rawptr, pre_draw: proc(data: rawptr)) -> DrawElem {
	e := _DrawElem_Empty
	e.data = data
	e.pre_draw = pre_draw
	return e
}
edraw :: proc(data: rawptr, draw: proc(data: rawptr)) -> DrawElem {
	e := _DrawElem_Empty
	e.data = data
	e.draw = draw
	return e
}
eextra_draw :: proc(data: rawptr, extra_draw: proc(data: rawptr)) -> DrawElem {
	e := _DrawElem_Empty
	e.data = data
	e.extra_draw = extra_draw
	return e
}

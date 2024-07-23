package main

import "core:fmt"
import "core:strconv"
import "core:slice"
import "core:math/rand"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

camera : rl.Camera2D

BLOCK_WIDTH :u32: 32
block : [BLOCK_WIDTH*BLOCK_WIDTH]u32

rnd : rand.Rand

FLAG_BOMB :u32= 0xff

get_index :: proc(x,y: int) -> int {
    return x+y*(auto_cast BLOCK_WIDTH)
}

in_range :: proc(x,y: int) -> bool {
    w :int= cast(int)BLOCK_WIDTH
    return !(x < 0 || y < 0 || x >= w || y >= w)
}

main :: proc() {
    rl.SetConfigFlags({rl.ConfigFlag.WINDOW_RESIZABLE})
    rl.InitWindow(800, 600, "Minesweeper")

    rl.SetTargetFPS(60)

    camera.zoom = 20

    rand.init(&rnd, 42)

    for i in 0..<160 do block[i] = FLAG_BOMB

    rand.shuffle(block[:], &rnd)

    for x in 0..<BLOCK_WIDTH {
        for y in 0..<BLOCK_WIDTH {
            check :: proc(count: ^int, x,y: int) {
                if in_range(x,y) && block[get_index(x,y)] == FLAG_BOMB {
                    count ^= count^ + 1
                }
            }
            x, y :int= auto_cast x, auto_cast y
            if block[get_index(x,y)] == FLAG_BOMB do continue
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
        }
    }

    last_position : rl.Vector2

    for !rl.WindowShouldClose() {
        camera.offset = rl.Vector2{ cast(f32)rl.GetScreenWidth()*0.5, cast(f32)rl.GetScreenHeight()*0.5 }

        speed :f32= 0.2
        if rl.IsKeyDown(.A) {
            camera.target.x -= speed
        } else if rl.IsKeyDown(.D) {
            camera.target.x += speed
        }
        if rl.IsKeyDown(.W) {
            camera.target.y -= speed
        } else if rl.IsKeyDown(.S) {
            camera.target.y += speed
        }

        if rl.IsMouseButtonPressed(.RIGHT) {
            last_position = rl.GetMousePosition()
        }
        if rl.IsMouseButtonDown(.RIGHT) {
            last := rl.GetScreenToWorld2D(last_position, camera)
            now := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)
            camera.target += last-now
        }

        zoom_speed_max, zoom_speed_min :f32= 1.2, 0.2
        zoom_max, zoom_min :f32= 36, 18
        zoom_speed :f32= ((camera.zoom-zoom_min)/(zoom_max-zoom_min)) * ( zoom_speed_max-zoom_speed_min ) + zoom_speed_min
        camera.zoom += rl.GetMouseWheelMove() * zoom_speed
        camera.zoom = clamp(camera.zoom, zoom_min, zoom_max)

        last_position = rl.GetMousePosition()

        rl.BeginDrawing()
        rl.ClearBackground(rl.Color{0,0,0,0})

        rl.BeginMode2D(camera)

        for x in 0..<BLOCK_WIDTH {
            for y in 0..<BLOCK_WIDTH {
                v := block[x+y*BLOCK_WIDTH]
                pos :rl.Vector2= {cast(f32)x,cast(f32)y}
                if v == FLAG_BOMB {
                    rl.DrawRectangleV(pos, {0.9, 0.9}, {140,50,40,255})
                    // rl.DrawRectangleV(pos, {0.8, 0.8}, {200,200,200,255})
                    rl.DrawRectangleV(pos, {0.8, 0.8}, {200,10,20,255})
                } else {
                    rl.DrawRectangleV(pos, {0.9, 0.9}, {155,155,155,255})
                    rl.DrawRectangleV(pos, {0.8, 0.8}, {200,200,200,255})
                    if v != 0 {
                        // rl.DrawText(, pos, )
                        rl.DrawTextEx(rl.GetFontDefault(), fmt.ctprintf("{}", v),
                            pos+{0.2, 0.1}, 0.8, 1, rl.Color{80, 120, 90, 255})
                    }
                }
            }
        }
        rl.DrawLine(-100, 0, 100, 0, rl.Color{255,255,0, 255})
        rl.DrawLine(0, -100, 0, 100, rl.Color{0,255,0, 255})

        rl.EndMode2D()

        rl.DrawText(fmt.ctprintf("zoom: {}", camera.zoom), 10, 10+30, 28, rl.Color{0,255,255,255})
        rl.DrawText(fmt.ctprintf("target: {}", camera.target), 10, 10+30+30, 28, rl.Color{0,255,255,255})
        rl.DrawText(fmt.ctprintf("offset: {}", camera.offset), 10, 10+30+30*2, 28, rl.Color{0,255,255,255})

        rl.EndDrawing()

    }
    rl.CloseWindow()
}

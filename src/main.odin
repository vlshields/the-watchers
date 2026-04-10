package game

import "vendor:raylib"
import dm "../dotmap"
import "core:fmt"
import "core:strings"
import "core:math/rand"

Game_State :: struct {
	map_data:      dm.Dot_Map,
	tile_textures: map[u8][dynamic]raylib.Texture2D,
	camera:        raylib.Camera2D,
	player:        Player,
	spear:         Spear,
	render_target: raylib.RenderTexture2D,
	screen_scale:  f32,
	screen_offset: raylib.Vector2,
	window_w:      i32,
	window_h:      i32,
	should_quit:   bool,
	bg_color:      raylib.Color,
}

@(private = "file")
gs: Game_State

@(private = "file")
update_screen_scale :: proc() {
	win_w := gs.window_w
	win_h := gs.window_h
	if win_w <= 0 || win_h <= 0 {
		win_w = raylib.GetScreenWidth()
		win_h = raylib.GetScreenHeight()
	}
	scale_x := f32(win_w) / f32(SCREEN_WIDTH)
	scale_y := f32(win_h) / f32(SCREEN_HEIGHT)
	gs.screen_scale = min(scale_x, scale_y)
	gs.screen_offset = {
		(f32(win_w) - f32(SCREEN_WIDTH) * gs.screen_scale) / 2,
		(f32(win_h) - f32(SCREEN_HEIGHT) * gs.screen_scale) / 2,
	}
}

// ---------------------------------------------------------------------------
// Map loading / unloading
// ---------------------------------------------------------------------------

@(private = "file")
load_map_data :: proc(path: string) -> bool {
	map_bytes, map_ok := read_entire_file(path)
	if !map_ok {
		fmt.eprintln("Failed to load map file:", path)
		return false
	}
	map_data, parse_ok := dm.parse_map(string(map_bytes))
	delete(map_bytes)
	if !parse_ok {
		fmt.eprintln("Failed to parse map:", path)
		return false
	}
	gs.map_data = map_data

	gs.tile_textures = make(map[u8][dynamic]raylib.Texture2D)
	for sym, td in gs.map_data.metadata {
		textures: [dynamic]raylib.Texture2D
		for tile_path in td.tiles {
			cpath := strings.clone_to_cstring(tile_path)
			defer delete(cpath)
			tex := raylib.LoadTexture(cpath)
			if tex.id > 0 {
				append(&textures, tex)
			} else {
				fmt.eprintln("Failed to load texture:", tile_path)
			}
		}
		gs.tile_textures[sym] = textures
	}

	// Assign random tile variants
	for sym, texs in gs.tile_textures {
		num_variants := len(texs)
		if num_variants > 1 {
			for &row in gs.map_data.grid {
				for &cell in row {
					if cell.symbol == sym {
						cell.tile_index = rand.int_max(num_variants)
					}
				}
			}
		}
	}

	return true
}

@(private = "file")
unload_map_data :: proc() {
	for _, &textures in gs.tile_textures {
		for &tex in textures {
			raylib.UnloadTexture(tex)
		}
		delete(textures)
	}
	delete(gs.tile_textures)
	dm.destroy_map(&gs.map_data)
}

// ---------------------------------------------------------------------------
// Init / Update / Shutdown
// ---------------------------------------------------------------------------

init :: proc() {
	raylib.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Inversion")

	when ODIN_ARCH != .wasm32 && ODIN_ARCH != .wasm64p32 {
		monitor := raylib.GetCurrentMonitor()
		screen_w := raylib.GetMonitorWidth(monitor)
		screen_h := raylib.GetMonitorHeight(monitor)
		raylib.SetWindowSize(screen_w, screen_h)
		raylib.ToggleFullscreen()
		raylib.SetTargetFPS(TARGET_FPS)
	}

	gs.render_target = raylib.LoadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT)
	raylib.SetTextureFilter(gs.render_target.texture, .POINT)
	update_screen_scale()

	gs.bg_color = {0x1a, 0x1a, 0x2e, 0xff}

	// Load map
	if !load_map_data("assets/maps/main_area_first.map") {
		gs.should_quit = true
		return
	}

	// Find player spawn
	spawn_pos := raylib.Vector2{100, 100}
	for row, ry in gs.map_data.grid {
		for cell, cx in row {
			if cell.symbol == 's' {
				td, has_meta := gs.map_data.metadata['s']
				if has_meta {
					spawn_key := dm.extract_kv(td.other, "spawn_point")
					if spawn_key == "player" {
						spawn_pos = {f32(cx) * TILE_SIZE + TILE_SIZE / 2, f32(ry) * TILE_SIZE}
					}
					delete(spawn_key)
				}
			}
		}
	}

	init_player(&gs.player, spawn_pos)
	init_spear(&gs.spear)

	gs.camera = raylib.Camera2D{
		zoom   = CAMERA_ZOOM,
		offset = {SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2},
		target = spawn_pos,
	}
}

update :: proc() {
	free_all(context.temp_allocator)

	dt := raylib.GetFrameTime()
	if dt > 0.05 {
		dt = 0.05
	}

	update_player(&gs.player, &gs.map_data, dt)
	update_spear(&gs.spear, &gs.player, dt)
	update_camera(dt)

	// Draw to virtual render target
	raylib.BeginTextureMode(gs.render_target)
	raylib.ClearBackground(gs.bg_color)

	raylib.BeginMode2D(gs.camera)
	draw_map()
	draw_player(&gs.player)
	draw_spear(&gs.spear, &gs.player)
	raylib.EndMode2D()

	raylib.EndTextureMode()

	// Blit render target scaled to window
	raylib.BeginDrawing()
	raylib.ClearBackground(raylib.BLACK)
	src := raylib.Rectangle{0, 0, f32(SCREEN_WIDTH), -f32(SCREEN_HEIGHT)}
	dst := raylib.Rectangle{
		gs.screen_offset.x,
		gs.screen_offset.y,
		f32(SCREEN_WIDTH) * gs.screen_scale,
		f32(SCREEN_HEIGHT) * gs.screen_scale,
	}
	raylib.DrawTexturePro(gs.render_target.texture, src, dst, {0, 0}, 0, raylib.WHITE)
	raylib.EndDrawing()
}

should_run :: proc() -> bool {
	return !raylib.WindowShouldClose() && !gs.should_quit
}

shutdown :: proc() {
	raylib.UnloadRenderTexture(gs.render_target)
	unload_map_data()
	unload_spear(&gs.spear)
	unload_player(&gs.player)
	raylib.CloseWindow()
}

parent_window_size_changed :: proc(w, h: int) {
	gs.window_w = i32(w)
	gs.window_h = i32(h)
	raylib.SetWindowSize(gs.window_w, gs.window_h)
	update_screen_scale()
}

set_web_mouse_pos :: proc(x, y: int) {
}

set_web_mouse_down :: proc(down: bool) {
}

// ---------------------------------------------------------------------------
// Camera
// ---------------------------------------------------------------------------

@(private = "file")
update_camera :: proc(dt: f32) {
	gs.camera.target = gs.player.pos

	map_w := f32(gs.map_data.width) * TILE_SIZE
	map_h := f32(gs.map_data.height) * TILE_SIZE
	half_w := f32(SCREEN_WIDTH) / (2 * gs.camera.zoom)
	half_h := f32(SCREEN_HEIGHT) / (2 * gs.camera.zoom)

	if gs.camera.target.x < half_w {
		gs.camera.target.x = half_w
	}
	if gs.camera.target.x > map_w - half_w {
		gs.camera.target.x = map_w - half_w
	}
	if gs.camera.target.y < half_h {
		gs.camera.target.y = half_h
	}
	if gs.camera.target.y > map_h - half_h {
		gs.camera.target.y = map_h - half_h
	}
}

// ---------------------------------------------------------------------------
// Map drawing
// ---------------------------------------------------------------------------

@(private = "file")
draw_map :: proc() {
	cam := gs.camera
	half_w := f32(SCREEN_WIDTH) / (2 * cam.zoom)
	half_h := f32(SCREEN_HEIGHT) / (2 * cam.zoom)
	min_x := int((cam.target.x - half_w) / TILE_SIZE) - 1
	max_x := int((cam.target.x + half_w) / TILE_SIZE) + 1
	min_y := int((cam.target.y - half_h) / TILE_SIZE) - 1
	max_y := int((cam.target.y + half_h) / TILE_SIZE) + 1

	if min_x < 0 {
		min_x = 0
	}
	if min_y < 0 {
		min_y = 0
	}
	if max_x >= gs.map_data.width {
		max_x = gs.map_data.width - 1
	}
	if max_y >= gs.map_data.height {
		max_y = gs.map_data.height - 1
	}

	for ry in min_y ..= max_y {
		if ry >= len(gs.map_data.grid) {
			break
		}
		row := gs.map_data.grid[ry]
		for cx in min_x ..= max_x {
			if cx >= len(row) {
				break
			}
			cell := row[cx]
			draw_x := f32(cx) * TILE_SIZE
			draw_y := f32(ry) * TILE_SIZE

			if cell.symbol == '.' || cell.symbol == 's' {
				continue
			}

			textures, has_tex := gs.tile_textures[cell.symbol]
			if !has_tex || len(textures) == 0 {
				continue
			}

			idx := cell.tile_index
			if idx >= len(textures) {
				idx = 0
			}
			tex := textures[idx]
			raylib.DrawTexture(tex, i32(draw_x), i32(draw_y), raylib.WHITE)
		}
	}
}

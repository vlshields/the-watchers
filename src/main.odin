package game

import "vendor:raylib"
import dm "../dotmap"
import "core:fmt"
import "core:strings"
import "core:math/rand"

Game_State :: struct {
	mode:          Game_Mode,
	menu:          Menu_State,
	hints:         Hints_State,
	map_data:      dm.Dot_Map,
	tile_textures: map[u8][dynamic]raylib.Texture2D,
	camera:        raylib.Camera2D,
	player:        Player,
	spear:         Spear,
	enemies:       [MAX_ENEMIES]Enemy,
	enemy_count:   int,
	signs:         [MAX_DECORATIVE_SIGNS]Decorative_Sign,
	sign_count:    int,
	waves:         Wave_Encounter,
	psy_projs:     [MAX_PSYCHIC_PROJECTILES]Psychic_Projectile,
	psy_proj_count: int,
	cherub_souls:  int,
	combat:        Combat_State,
	music:         raylib.Music,
	music_loaded:  bool,
	hit_flash_shader: raylib.Shader,
	render_target:    raylib.RenderTexture2D,
	screen_scale:  f32,
	screen_offset: raylib.Vector2,
	window_w:      i32,
	window_h:      i32,
	should_quit:   bool,
	bg_color:      raylib.Color,
}

Game_Mode :: enum {
	Menu,
	Playing,
	Paused,
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
	raylib.InitAudioDevice()

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
	init_enemies(&gs.enemies, &gs.enemy_count, &gs.map_data)
	init_decorative_signs(&gs.signs, &gs.sign_count, &gs.map_data)
	init_wave_encounter(&gs.waves, &gs.map_data)
	init_combat(&gs.combat)
	init_psychic_projectiles()
	init_sfx()
	init_menu(&gs.menu)
	init_hints(&gs.hints)
	init_music()

	gs.camera = raylib.Camera2D{
		zoom   = CAMERA_ZOOM,
		offset = {SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2},
		target = spawn_pos,
	}

	// White flash shader for player damage
	when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
		fs :: `#version 100
precision mediump float;
varying vec2 fragTexCoord;
varying vec4 fragColor;
uniform sampler2D texture0;
void main() {
    vec4 texel = texture2D(texture0, fragTexCoord);
    gl_FragColor = vec4(1.0, 1.0, 1.0, texel.a) * fragColor;
}`
		gs.hit_flash_shader = raylib.LoadShaderFromMemory(nil, fs)
	} else {
		fs :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
out vec4 finalColor;
void main() {
    vec4 texel = texture(texture0, fragTexCoord);
    finalColor = vec4(1.0, 1.0, 1.0, texel.a) * fragColor;
}`
		gs.hit_flash_shader = raylib.LoadShaderFromMemory(nil, fs)
	}
}

update :: proc() {
	free_all(context.temp_allocator)

	dt := raylib.GetFrameTime()
	if dt > 0.05 {
		dt = 0.05
	}

	update_music()
	update_menu_input_mode(&gs.menu)
	if gs.mode == .Menu || gs.mode == .Paused {
		update_menu(&gs.menu)
		draw_menu_frame(&gs.menu)
		return
	}

	if raylib.IsKeyPressed(.ESCAPE) || (gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .MIDDLE_RIGHT)) {
		gs.mode = .Paused
		gs.menu.screen = .Main
		gs.menu.selected = 0
		play_sfx(.Ui_Back)
		draw_menu_frame(&gs.menu)
		return
	}

	prev_spear_state := gs.spear.state
	prev_throw_phase := gs.combat.throw_phase
	prev_player_teleporting := gs.player.is_teleporting
	prev_active_signs := active_sign_count(&gs.signs, gs.sign_count)
	update_player(&gs.player, &gs.map_data, dt)
	update_spear(&gs.spear, &gs.player, dt)
	update_wave_encounter(
		&gs.waves,
		&gs.player,
		&gs.map_data,
		&gs.enemies,
		&gs.enemy_count,
		gs.camera,
	)
	enemy_states_before := snapshot_enemy_states(&gs.enemies, gs.enemy_count)
	update_enemies(
		&gs.enemies,
		gs.enemy_count,
		&gs.map_data,
		&gs.player,
		&gs.psy_projs,
		&gs.psy_proj_count,
		dt,
	)
	collect_cherub_souls(&enemy_states_before, &gs.enemies, gs.enemy_count, &gs.cherub_souls)
	update_psychic_projectiles(&gs.psy_projs, &gs.psy_proj_count, &gs.player, &gs.map_data, dt)
	update_combat(
		&gs.combat,
		&gs.player,
		&gs.spear,
		&gs.map_data,
		&gs.enemies,
		gs.enemy_count,
		&gs.signs,
		gs.sign_count,
		dt,
	)
	hint_events := Hint_Events{
		spear_summoned = prev_spear_state == .Inactive && gs.spear.state == .Spawning,
		spear_thrown = prev_throw_phase == .None && gs.combat.throw_phase != .None,
		teleported = !prev_player_teleporting && gs.player.is_teleporting,
		sign_used = active_sign_count(&gs.signs, gs.sign_count) < prev_active_signs,
	}
	update_camera(dt)
	update_hints(
		&gs.hints,
		hint_events,
		&gs.player,
		&gs.enemies,
		gs.enemy_count,
		&gs.signs,
		gs.sign_count,
		gs.camera,
	)

	// Draw to virtual render target
	raylib.BeginTextureMode(gs.render_target)
	raylib.ClearBackground(gs.bg_color)

	raylib.BeginMode2D(gs.camera)
	draw_map(gs.camera)
	draw_decorative_signs(&gs.signs, gs.sign_count)
	draw_enemies(&gs.enemies, gs.enemy_count, gs.hit_flash_shader)
	draw_psychic_projectiles(&gs.psy_projs, gs.psy_proj_count)
	player_flashing := gs.player.hit_timer > 0 && int(gs.player.hit_timer / 0.05) % 2 == 0
	if player_flashing {
		raylib.BeginShaderMode(gs.hit_flash_shader)
	}
	draw_player(&gs.player)
	if player_flashing {
		raylib.EndShaderMode()
	}
	draw_spear(&gs.spear, &gs.player)
	draw_combat(&gs.combat, &gs.enemies, gs.enemy_count, &gs.signs, gs.sign_count)
	raylib.EndMode2D()

	draw_hud(&gs.player, gs.cherub_souls)
	draw_hints(&gs.hints, gs.menu.input_mode, gs.menu.hints_enabled)

	raylib.EndTextureMode()

	// Blit render target scaled to window
	draw_render_target_to_window()
}

@(private = "file")
init_music :: proc() {
	if !raylib.IsAudioDeviceReady() {
		return
	}

	gs.music = raylib.LoadMusicStream("assets/audio/soundtrack/main_theme.ogg")
	if !raylib.IsMusicValid(gs.music) {
		return
	}

	gs.music.looping = true
	raylib.SetMusicVolume(gs.music, gs.menu.music_volume)
	raylib.PlayMusicStream(gs.music)
	gs.music_loaded = true
}

@(private = "file")
update_music :: proc() {
	if gs.music_loaded {
		raylib.UpdateMusicStream(gs.music)
	}
}

set_music_volume :: proc(volume: f32) {
	gs.menu.music_volume = clamp01(volume)
	if gs.music_loaded {
		raylib.SetMusicVolume(gs.music, gs.menu.music_volume)
	}
}

play_game_from_menu :: proc() {
	gs.mode = .Playing
}

resume_game_from_pause :: proc() {
	gs.mode = .Playing
}

quit_from_menu :: proc() {
	gs.should_quit = true
}

menu_is_paused :: proc() -> bool {
	return gs.mode == .Paused
}

@(private = "file")
active_sign_count :: proc(signs: ^[MAX_DECORATIVE_SIGNS]Decorative_Sign, count: int) -> int {
	result := 0
	for i in 0 ..< count {
		if signs[i].active {
			result += 1
		}
	}
	return result
}

@(private = "file")
snapshot_enemy_states :: proc(enemies: ^[MAX_ENEMIES]Enemy, count: int) -> [MAX_ENEMIES]Enemy_State {
	result: [MAX_ENEMIES]Enemy_State
	for i in 0 ..< count {
		result[i] = enemies[i].state
	}
	return result
}

@(private = "file")
collect_cherub_souls :: proc(
	prev_states: ^[MAX_ENEMIES]Enemy_State,
	enemies: ^[MAX_ENEMIES]Enemy,
	count: int,
	cherub_souls: ^int,
) {
	for i in 0 ..< count {
		e := &enemies[i]
		if prev_states[i] != .Dead && e.state == .Dead && enemy_gives_cherub_soul(e) {
			cherub_souls^ += 1
		}
	}
}

@(private = "file")
enemy_gives_cherub_soul :: proc(e: ^Enemy) -> bool {
	return e.type == .Cherub || e.type == .Mutant_Cherub
}

should_run :: proc() -> bool {
	return !raylib.WindowShouldClose() && !gs.should_quit
}

shutdown :: proc() {
	raylib.UnloadShader(gs.hit_flash_shader)
	raylib.UnloadRenderTexture(gs.render_target)
	if gs.music_loaded {
		raylib.UnloadMusicStream(gs.music)
	}
	unload_sfx()
	unload_map_data()
	unload_combat()
	unload_psychic_projectiles()
	unload_decorative_signs()
	unload_enemies()
	unload_spear(&gs.spear)
	unload_player(&gs.player)
	if raylib.IsAudioDeviceReady() {
		raylib.CloseAudioDevice()
	}
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

@(private = "file")
draw_menu_frame :: proc(menu: ^Menu_State) {
	raylib.BeginTextureMode(gs.render_target)
	raylib.ClearBackground(MENU_BG)
	draw_menu_contents(menu)
	raylib.EndTextureMode()
	draw_render_target_to_window()
}

virtual_mouse_pos :: proc() -> (raylib.Vector2, bool) {
	mouse := raylib.GetMousePosition()
	if gs.screen_scale <= 0 {
		return mouse, false
	}

	pos := raylib.Vector2{
		(mouse.x - gs.screen_offset.x) / gs.screen_scale,
		(mouse.y - gs.screen_offset.y) / gs.screen_scale,
	}
	in_bounds := pos.x >= 0 && pos.x <= SCREEN_WIDTH && pos.y >= 0 && pos.y <= SCREEN_HEIGHT
	return pos, in_bounds
}

@(private = "file")
draw_render_target_to_window :: proc() {
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

// ---------------------------------------------------------------------------
// Camera
// ---------------------------------------------------------------------------

@(private = "file")
update_camera :: proc(dt: f32) {
	desired := gs.player.pos

	map_w := f32(gs.map_data.width) * TILE_SIZE
	map_h := f32(gs.map_data.height) * TILE_SIZE
	half_w := f32(SCREEN_WIDTH) / (2 * gs.camera.zoom)
	half_h := f32(SCREEN_HEIGHT) / (2 * gs.camera.zoom)

	if desired.x < half_w {
		desired.x = half_w
	}
	if desired.x > map_w - half_w {
		desired.x = map_w - half_w
	}
	if desired.y < half_h {
		desired.y = half_h
	}
	if desired.y > map_h - half_h {
		desired.y = map_h - half_h
	}

	t := dt * CAMERA_FOLLOW_SPEED
	if t > 1 {
		t = 1
	}
	eased := raylib.EaseCubicOut(t, 0, 1, 1)
	gs.camera.target.x += (desired.x - gs.camera.target.x) * eased
	gs.camera.target.y += (desired.y - gs.camera.target.y) * eased
}

// ---------------------------------------------------------------------------
// Map drawing
// ---------------------------------------------------------------------------

@(private = "file")
draw_map :: proc(cam: raylib.Camera2D) {
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

			if cell.symbol == '.' || cell.symbol == 's' || cell.symbol == 'c' ||
				cell.symbol == 'g' || cell.symbol == 'm' || cell.symbol == '@' {
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

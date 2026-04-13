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
	main_menu_music: raylib.Music,
	cutscene_music: raylib.Music,
	music_loaded:  bool,
	main_menu_music_loaded: bool,
	cutscene_music_loaded: bool,
	parallax_bg:   [PARALLAX_LAYER_COUNT]raylib.Texture2D,
	parallax_origin: raylib.Vector2,
	hit_flash_shader: raylib.Shader,
	render_target:    raylib.RenderTexture2D,
	screen_scale:  f32,
	screen_offset: raylib.Vector2,
	window_w:      i32,
	window_h:      i32,
	should_quit:   bool,
	bg_color:      raylib.Color,
	cutscene_line: int,
	cutscene_shake: f32,
	cutscene_played: bool,
}

Game_Mode :: enum {
	Menu,
	Cutscene,
	Playing,
	Paused,
	Game_Over,
	Victory,
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
	init_parallax_background()

	if !init_playthrough() {
		gs.should_quit = true
		return
	}
	init_sfx()
	init_menu(&gs.menu)
	init_music()

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
	if gs.mode == .Cutscene {
		update_cutscene(dt)
		draw_cutscene_frame()
		return
	}
	if gs.mode == .Menu || gs.mode == .Paused || gs.mode == .Game_Over || gs.mode == .Victory {
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
	if gs.cherub_souls >= WIN_CHERUB_SOULS {
		enter_victory()
		draw_menu_frame(&gs.menu)
		return
	}
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
	if gs.player.hp <= 0 {
		enter_game_over()
		draw_menu_frame(&gs.menu)
		return
	}
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

	draw_parallax_background(gs.camera)
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
	if raylib.IsMusicValid(gs.music) {
		gs.music.looping = true
		raylib.SetMusicVolume(gs.music, gs.menu.music_volume)
		gs.music_loaded = true
	}

	gs.main_menu_music = raylib.LoadMusicStream("assets/audio/soundtrack/main_menu.ogg")
	if raylib.IsMusicValid(gs.main_menu_music) {
		gs.main_menu_music.looping = true
		raylib.SetMusicVolume(gs.main_menu_music, gs.menu.music_volume)
		gs.main_menu_music_loaded = true
	}

	gs.cutscene_music = raylib.LoadMusicStream("assets/audio/soundtrack/cutscene.ogg")

	gs.cutscene_music.looping = true
	if raylib.IsMusicValid(gs.cutscene_music) {
		raylib.SetMusicVolume(gs.cutscene_music, gs.menu.music_volume)
		gs.cutscene_music_loaded = true
	}
	if gs.main_menu_music_loaded {
		raylib.PlayMusicStream(gs.main_menu_music)
	}
}

@(private = "file")
update_music :: proc() {
	if gs.music_loaded && raylib.IsMusicStreamPlaying(gs.music) {
		raylib.UpdateMusicStream(gs.music)
	}
	if gs.main_menu_music_loaded && raylib.IsMusicStreamPlaying(gs.main_menu_music) {
		raylib.UpdateMusicStream(gs.main_menu_music)
	}
	if gs.cutscene_music_loaded && raylib.IsMusicStreamPlaying(gs.cutscene_music) {
		raylib.UpdateMusicStream(gs.cutscene_music)
	}
}

set_music_volume :: proc(volume: f32) {
	gs.menu.music_volume = clamp01(volume)
	if gs.music_loaded {
		raylib.SetMusicVolume(gs.music, gs.menu.music_volume)
	}
	if gs.main_menu_music_loaded {
		raylib.SetMusicVolume(gs.main_menu_music, gs.menu.music_volume)
	}
	if gs.cutscene_music_loaded {
		raylib.SetMusicVolume(gs.cutscene_music, gs.menu.music_volume)
	}
}

play_game_from_menu :: proc() {
	if !gs.cutscene_played {
		enter_cutscene()
		return
	}
	gs.mode = .Playing
	if gs.main_menu_music_loaded {
		raylib.StopMusicStream(gs.main_menu_music)
	}
	if gs.music_loaded {
		raylib.PlayMusicStream(gs.music)
	}
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

menu_is_game_over :: proc() -> bool {
	return gs.mode == .Game_Over
}

menu_is_victory :: proc() -> bool {
	return gs.mode == .Victory
}

restart_game_from_game_over :: proc() {
	unload_playthrough()
	if !init_playthrough() {
		gs.should_quit = true
		return
	}
	gs.mode = .Playing
}

return_to_main_from_game_over :: proc() {
	unload_playthrough()
	if !init_playthrough() {
		gs.should_quit = true
		return
	}
	gs.mode = .Menu
	gs.menu.screen = .Main
	gs.menu.selected = 0
	if gs.music_loaded {
		raylib.StopMusicStream(gs.music)
	}
	if gs.main_menu_music_loaded {
		raylib.PlayMusicStream(gs.main_menu_music)
	}
}

restart_game_from_victory :: proc() {
	restart_game_from_game_over()
}

return_to_main_from_victory :: proc() {
	return_to_main_from_game_over()
}

Cutscene_Line :: struct {
	speaker: cstring,
	text:    cstring,
	shake:   bool,
}

@(private = "file")
MISSION_SCENE : [CUTSCENE_LINE_COUNT]Cutscene_Line : {
	{"NARRATOR", "Gadreela wakes up in a strange and unfamiliar place.\nIt feels void of space and substance, like a vacuum.\nShe hears a voice...", false},
	{"SARIEL",   "Gadreela, you have made it to our target.", false},
	{"GADREELA", "General Sariel? Where am I?", false},
	{"SARIEL",   "The teleportation worked. You are on Mt. Hermon,\nthe capital fortress of the Watchers,\nour nefarious captors.", false},
	{"GADREELA", "Ah, yes. I remember my mission now.\nWe need to power our secret weapon, the Laseract.", false},
	{"SARIEL",   "Yes. Those vile Watchers have created several abominations,\nCherubs being our primary target. The psychic energy bound\nto their souls can power the Laseract enough to destroy Mt. Hermon.", false},
	{"GADREELA", "I am ready to bring destruction upon evil\nand free our people once and for all.", false},
	{"SARIEL",   "Then go, and return here once you have collected\nthirty cherub souls. I will be waiting.", false},
}

@(private = "file")
enter_cutscene :: proc() {
	gs.cutscene_line = 0
	gs.cutscene_shake = 0
	gs.mode = .Cutscene
	if gs.main_menu_music_loaded {
		raylib.StopMusicStream(gs.main_menu_music)
	}
	if gs.music_loaded {
		raylib.StopMusicStream(gs.music)
	}
	if gs.cutscene_music_loaded {
		raylib.PlayMusicStream(gs.cutscene_music)
	}
}

@(private = "file")
finish_cutscene :: proc() {
	gs.cutscene_played = true
	gs.mode = .Playing
	if gs.cutscene_music_loaded {
		raylib.StopMusicStream(gs.cutscene_music)
	}
	if gs.music_loaded {
		raylib.PlayMusicStream(gs.music)
	}
}

@(private = "file")
enter_game_over :: proc() {
	gs.mode = .Game_Over
	gs.menu.screen = .Main
	gs.menu.selected = 0
}

@(private = "file")
enter_victory :: proc() {
	gs.mode = .Victory
	gs.menu.screen = .Main
	gs.menu.selected = 0
}

@(private = "file")
init_playthrough :: proc() -> bool {
	if !load_map_data("assets/maps/main_area_first.map") {
		return false
	}

	spawn_pos := find_player_spawn()
	init_player(&gs.player, spawn_pos)
	init_spear(&gs.spear)
	init_enemies(&gs.enemies, &gs.enemy_count, &gs.map_data)
	init_decorative_signs(&gs.signs, &gs.sign_count, &gs.map_data)
	init_wave_encounter(&gs.waves, &gs.map_data)
	init_combat(&gs.combat)
	init_psychic_projectiles()
	init_hints(&gs.hints)
	gs.psy_proj_count = 0
	gs.cherub_souls = 0
	gs.camera = raylib.Camera2D{
		zoom   = CAMERA_ZOOM,
		offset = {SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2},
		target = spawn_pos,
	}
	gs.parallax_origin = gs.camera.target
	return true
}

@(private = "file")
unload_playthrough :: proc() {
	unload_map_data()
	unload_combat()
	unload_psychic_projectiles()
	unload_decorative_signs()
	unload_enemies()
	unload_spear(&gs.spear)
	unload_player(&gs.player)
}

@(private = "file")
find_player_spawn :: proc() -> raylib.Vector2 {
	spawn_pos := raylib.Vector2{100, 100}
	for row, ry in gs.map_data.grid {
		for cell, cx in row {
			if cell.symbol != 's' {
				continue
			}
			td, has_meta := gs.map_data.metadata['s']
			if !has_meta {
				continue
			}
			spawn_key := dm.extract_kv(td.other, "spawn_point")
			if spawn_key == "player" {
				spawn_pos = {f32(cx) * TILE_SIZE + TILE_SIZE / 2, f32(ry) * TILE_SIZE}
			}
			delete(spawn_key)
		}
	}
	return spawn_pos
}

@(private = "file")
update_cutscene :: proc(dt: f32) {
	if cutscene_back_pressed() {
		finish_cutscene()
		return
	}

	if gs.cutscene_shake > 0 {
		gs.cutscene_shake -= dt
	}

	if cutscene_accept_pressed() {
		gs.cutscene_line += 1
		if gs.cutscene_line >= CUTSCENE_LINE_COUNT {
			finish_cutscene()
			return
		}
		scene := MISSION_SCENE
		if scene[gs.cutscene_line].shake {
			gs.cutscene_shake = CUTSCENE_SHAKE_DURATION
		}
	}
}

@(private = "file")
draw_cutscene_frame :: proc() {
	raylib.BeginTextureMode(gs.render_target)
	draw_cutscene()
	raylib.EndTextureMode()
	draw_render_target_to_window()
}

@(private = "file")
draw_cutscene :: proc() {
	raylib.ClearBackground(raylib.BLACK)

	scene := MISSION_SCENE
	line := scene[gs.cutscene_line]
	shake_x: i32 = 0
	shake_y: i32 = 0
	if gs.cutscene_shake > 0 {
		intensity := gs.cutscene_shake / CUTSCENE_SHAKE_DURATION
		mag := intensity * 4
		shake_x = i32(rand.float32_range(-mag, mag))
		shake_y = i32(rand.float32_range(-mag, mag))
	}

	box_x := i32(40)
	box_w := i32(SCREEN_WIDTH) - box_x * 2
	box_h := i32(112)
	box_y := i32(SCREEN_HEIGHT) - box_h - 20
	raylib.DrawRectangle(box_x + shake_x, box_y + shake_y, box_w, box_h, {20, 20, 20, 230})
	raylib.DrawRectangleLines(box_x + shake_x, box_y + shake_y, box_w, box_h, {100, 100, 100, 200})

	speaker_color := raylib.Color{0xd8, 0xd1, 0xbc, 0xff}
	if line.speaker == "SARIEL" {
		speaker_color = {0x9c, 0xc9, 0xff, 0xff}
	} else if line.speaker == "GADREELA" {
		speaker_color = {0xff, 0xd2, 0x75, 0xff}
	}
	raylib.DrawText(line.speaker, box_x + 10 + shake_x, box_y + 8 + shake_y, 10, speaker_color)
	raylib.DrawText(line.text, box_x + 10 + shake_x, box_y + 26 + shake_y, 10, raylib.WHITE)

	prompt: cstring = gamepad_active() ? "A to continue" : "ENTER to continue"
	prompt_w := raylib.MeasureText(prompt, 6)
	raylib.DrawText(prompt, (SCREEN_WIDTH - prompt_w) / 2, SCREEN_HEIGHT - 14, 6, {150, 150, 150, 255})
	skip: cstring = gamepad_active() ? "B to skip" : "ESC to skip"
	raylib.DrawText(skip, SCREEN_WIDTH - 70, 5, 6, {100, 100, 100, 255})
}

@(private = "file")
cutscene_accept_pressed :: proc() -> bool {
	if raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE) {
		return true
	}
	return gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_FACE_DOWN)
}

@(private = "file")
cutscene_back_pressed :: proc() -> bool {
	if raylib.IsKeyPressed(.ESCAPE) || raylib.IsKeyPressed(.BACKSPACE) {
		return true
	}
	return gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_FACE_RIGHT)
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
	if gs.main_menu_music_loaded {
		raylib.UnloadMusicStream(gs.main_menu_music)
	}
	if gs.cutscene_music_loaded {
		raylib.UnloadMusicStream(gs.cutscene_music)
	}
	unload_parallax_background()
	unload_sfx()
	unload_playthrough()
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
// Parallax background
// ---------------------------------------------------------------------------

@(private = "file")
init_parallax_background :: proc() {
	paths := [?]string{
		"assets/sprites/parralax_bg/bg0.png",
		"assets/sprites/parralax_bg/bg1.png",
		"assets/sprites/parralax_bg/bg2.png",
		"assets/sprites/parralax_bg/bg3.png",
		"assets/sprites/parralax_bg/bg4.png",
	}
	for path, i in paths {
		cpath := strings.clone_to_cstring(path)
		defer delete(cpath)
		gs.parallax_bg[i] = raylib.LoadTexture(cpath)
		if gs.parallax_bg[i].id <= 0 {
			fmt.eprintln("Failed to load parallax background:", path)
		}
	}
}

@(private = "file")
unload_parallax_background :: proc() {
	for tex in gs.parallax_bg {
		if tex.id > 0 {
			raylib.UnloadTexture(tex)
		}
	}
}

@(private = "file")
draw_parallax_background :: proc(cam: raylib.Camera2D) {
	parallax := [?]f32{0.02, 0.05, 0.09, 0.14, 0.22}
	for tex, i in gs.parallax_bg {
		if tex.id <= 0 {
			continue
		}
		draw_tiled_parallax_layer(tex, cam.target, parallax[i])
	}
}

@(private = "file")
draw_tiled_parallax_layer :: proc(tex: raylib.Texture2D, camera_target: raylib.Vector2, amount: f32) {
	w := f32(tex.width)
	h := f32(tex.height)
	if w <= 0 || h <= 0 {
		return
	}

	camera_delta := raylib.Vector2{
		camera_target.x - gs.parallax_origin.x,
		camera_target.y - gs.parallax_origin.y,
	}
	x0 := wrap_parallax_offset(-camera_delta.x * amount, w)
	tile_step := w - 2
	for x := x0; x < f32(SCREEN_WIDTH); x += tile_step {
		raylib.DrawTexture(tex, i32(x), 0, raylib.WHITE)
	}
}

@(private = "file")
wrap_parallax_offset :: proc(value, size: f32) -> f32 {
	result := value
	for result <= -size {
		result += size
	}
	for result > 0 {
		result -= size
	}
	return result
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

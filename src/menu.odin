package game

import "vendor:raylib"
import "core:fmt"
import "core:strings"

Menu_Screen :: enum {
	Main,
	Options,
	Controls,
}

Menu_Input_Mode :: enum {
	Keyboard,
	Gamepad,
}

Menu_Slider :: enum {
	None,
	Music,
	Sfx,
}

Menu_State :: struct {
	screen:          Menu_Screen,
	selected:        int,
	input_mode:      Menu_Input_Mode,
	music_volume:    f32,
	sfx_volume:      f32,
	hints_enabled:   bool,
	dragging_slider: Menu_Slider,
}

MENU_PANEL_X :: f32(176)
MENU_BUTTON_X :: f32(220)
MENU_BUTTON_W :: f32(200)
MENU_BUTTON_H :: f32(34)
MENU_MAIN_BUTTON_Y :: f32(138)
MENU_ROW_GAP :: f32(44)
MENU_OPTIONS_X :: f32(156)
MENU_OPTIONS_W :: f32(328)
MENU_OPTIONS_Y :: f32(112)
MENU_SLIDER_X :: f32(284)
MENU_SLIDER_W :: f32(146)
MENU_SLIDER_H :: f32(8)

MENU_BG :: raylib.Color{0x10, 0x0d, 0x14, 0xff}
MENU_PANEL :: raylib.Color{0x22, 0x1a, 0x26, 0xee}
MENU_PANEL_LINE :: raylib.Color{0x76, 0x68, 0x72, 0xff}
MENU_BUTTON :: raylib.Color{0x31, 0x27, 0x32, 0xff}
MENU_BUTTON_HOVER :: raylib.Color{0x58, 0x46, 0x48, 0xff}
MENU_ACCENT :: raylib.Color{0xd8, 0xd1, 0xbc, 0xff}
MENU_MUTED :: raylib.Color{0xa2, 0x98, 0x9b, 0xff}
MENU_DARK :: raylib.Color{0x0a, 0x08, 0x0c, 0xff}

init_menu :: proc(menu: ^Menu_State) {
	menu.screen = .Main
	menu.selected = 0
	menu.input_mode = .Keyboard
	menu.music_volume = 0.65
	menu.sfx_volume = 1.0
	menu.hints_enabled = true
	menu.dragging_slider = .None
	set_sfx_volume(menu.sfx_volume)
}

update_menu_input_mode :: proc(menu: ^Menu_State) {
	keyboard_pressed :=
		raylib.IsKeyPressed(.UP) || raylib.IsKeyPressed(.DOWN) ||
		raylib.IsKeyPressed(.LEFT) || raylib.IsKeyPressed(.RIGHT) ||
		raylib.IsKeyPressed(.W) || raylib.IsKeyPressed(.A) ||
		raylib.IsKeyPressed(.S) || raylib.IsKeyPressed(.D) ||
		raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE) ||
		raylib.IsKeyPressed(.ESCAPE)
	if keyboard_pressed || raylib.IsMouseButtonPressed(.LEFT) {
		menu.input_mode = .Keyboard
	}

	if !gamepad_active() {
		return
	}

	stick_x := raylib.GetGamepadAxisMovement(GAMEPAD_ID, .LEFT_X)
	stick_y := raylib.GetGamepadAxisMovement(GAMEPAD_ID, .LEFT_Y)
	gamepad_pressed :=
		raylib.IsGamepadButtonPressed(GAMEPAD_ID, .LEFT_FACE_UP) ||
		raylib.IsGamepadButtonPressed(GAMEPAD_ID, .LEFT_FACE_DOWN) ||
		raylib.IsGamepadButtonPressed(GAMEPAD_ID, .LEFT_FACE_LEFT) ||
		raylib.IsGamepadButtonPressed(GAMEPAD_ID, .LEFT_FACE_RIGHT) ||
		raylib.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_FACE_DOWN) ||
		raylib.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_FACE_RIGHT) ||
		raylib.IsGamepadButtonPressed(GAMEPAD_ID, .MIDDLE_RIGHT) ||
		stick_x < -STICK_DEADZONE || stick_x > STICK_DEADZONE ||
		stick_y < -STICK_DEADZONE || stick_y > STICK_DEADZONE
	if gamepad_pressed {
		menu.input_mode = .Gamepad
	}
}

update_menu :: proc(menu: ^Menu_State) {
	mouse, mouse_valid := virtual_mouse_pos()
	mouse_pressed := mouse_valid && raylib.IsMouseButtonPressed(.LEFT)
	mouse_down := mouse_valid && raylib.IsMouseButtonDown(.LEFT)

	if !mouse_down {
		menu.dragging_slider = .None
	}

	if menu.screen == .Main {
		update_main_menu(menu, mouse, mouse_valid, mouse_pressed)
	} else if menu.screen == .Options {
		update_options_menu(menu, mouse, mouse_valid, mouse_pressed, mouse_down)
	} else {
		update_controls_menu(menu, mouse, mouse_valid, mouse_pressed)
	}
}

draw_menu_contents :: proc(menu: ^Menu_State) {
	draw_menu_background(menu_is_paused() && menu.screen == .Main)
	if menu.screen == .Main {
		draw_main_menu(menu)
	} else if menu.screen == .Options {
		draw_options_menu(menu)
	} else {
		draw_controls_menu(menu)
	}
}

@(private = "file")
update_main_menu :: proc(menu: ^Menu_State, mouse: raylib.Vector2, mouse_valid, mouse_pressed: bool) {
	for i in 0 ..< 4 {
		button_rect := main_button_rect(i)
		if menu_is_paused() {
			button_rect = pause_button_rect(i)
		}
		if mouse_valid && raylib.CheckCollisionPointRec(mouse, button_rect) {
			menu.selected = i
			if mouse_pressed {
				activate_main_menu(menu)
			}
		}
	}

	update_vertical_selection(menu, 4)
	if menu_accept_pressed() {
		activate_main_menu(menu)
	}
	if menu_is_paused() && menu_back_pressed() {
		play_sfx(.Ui_Back)
		resume_game_from_pause()
	}
}

@(private = "file")
update_options_menu :: proc(
	menu: ^Menu_State,
	mouse: raylib.Vector2,
	mouse_valid, mouse_pressed, mouse_down: bool,
) {
	for i in 0 ..< 4 {
		if mouse_valid && raylib.CheckCollisionPointRec(mouse, options_row_rect(i)) {
			menu.selected = i
			if mouse_pressed {
				if i == 0 {
					menu.dragging_slider = .Music
					set_music_volume(slider_value_from_mouse(mouse))
				} else if i == 1 {
					menu.dragging_slider = .Sfx
					set_sfx_volume(slider_value_from_mouse(mouse))
					menu.sfx_volume = sfx_volume()
				} else if i == 2 {
					menu.hints_enabled = !menu.hints_enabled
					play_sfx(.Ui_Confirm)
				} else {
					back_to_main(menu)
				}
			}
		}
	}

	if mouse_down && menu.dragging_slider == .Music {
		set_music_volume(slider_value_from_mouse(mouse))
	}
	if mouse_down && menu.dragging_slider == .Sfx {
		set_sfx_volume(slider_value_from_mouse(mouse))
		menu.sfx_volume = sfx_volume()
	}

	update_vertical_selection(menu, 4)
	if menu_left_pressed() {
		adjust_selected_option(menu, -0.05)
	}
	if menu_right_pressed() {
		adjust_selected_option(menu, 0.05)
	}
	if menu_accept_pressed() {
		if menu.selected == 2 {
			menu.hints_enabled = !menu.hints_enabled
			play_sfx(.Ui_Confirm)
		} else if menu.selected == 3 {
			back_to_main(menu)
		}
	}
	if menu_back_pressed() {
		back_to_main(menu)
	}
}

@(private = "file")
update_controls_menu :: proc(menu: ^Menu_State, mouse: raylib.Vector2, mouse_valid, mouse_pressed: bool) {
	if mouse_valid && raylib.CheckCollisionPointRec(mouse, controls_back_rect()) {
		menu.selected = 0
		if mouse_pressed {
			back_to_main(menu)
		}
	}
	if menu_accept_pressed() || menu_back_pressed() {
		back_to_main(menu)
	}
}

@(private = "file")
update_vertical_selection :: proc(menu: ^Menu_State, count: int) {
	if menu_down_pressed() {
		menu.selected = (menu.selected + 1) % count
		play_sfx(.Ui_Confirm)
	}
	if menu_up_pressed() {
		menu.selected = (menu.selected + count - 1) % count
		play_sfx(.Ui_Confirm)
	}
}

@(private = "file")
activate_main_menu :: proc(menu: ^Menu_State) {
	if menu.selected == 0 {
		play_sfx(.Ui_Confirm)
		if menu_is_paused() {
			resume_game_from_pause()
		} else {
			play_game_from_menu()
		}
	} else if menu.selected == 1 {
		menu.screen = .Options
		menu.selected = 0
		play_sfx(.Ui_Confirm)
	} else if menu.selected == 2 {
		menu.screen = .Controls
		menu.selected = 0
		play_sfx(.Ui_Confirm)
	} else {
		play_sfx(.Ui_Back)
		quit_from_menu()
	}
}

@(private = "file")
back_to_main :: proc(menu: ^Menu_State) {
	menu.screen = .Main
	menu.selected = 0
	menu.dragging_slider = .None
	play_sfx(.Ui_Back)
}

@(private = "file")
adjust_selected_option :: proc(menu: ^Menu_State, delta: f32) {
	if menu.selected == 0 {
		set_music_volume(menu.music_volume + delta)
		play_sfx(.Ui_Confirm)
	} else if menu.selected == 1 {
		set_sfx_volume(menu.sfx_volume + delta)
		menu.sfx_volume = sfx_volume()
		play_sfx(.Ui_Confirm)
	}
}

@(private = "file")
menu_up_pressed :: proc() -> bool {
	if raylib.IsKeyPressed(.W) || raylib.IsKeyPressed(.UP) {
		return true
	}
	return gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .LEFT_FACE_UP)
}

@(private = "file")
menu_down_pressed :: proc() -> bool {
	if raylib.IsKeyPressed(.S) || raylib.IsKeyPressed(.DOWN) {
		return true
	}
	return gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .LEFT_FACE_DOWN)
}

@(private = "file")
menu_left_pressed :: proc() -> bool {
	if raylib.IsKeyPressed(.A) || raylib.IsKeyPressed(.LEFT) {
		return true
	}
	return gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .LEFT_FACE_LEFT)
}

@(private = "file")
menu_right_pressed :: proc() -> bool {
	if raylib.IsKeyPressed(.D) || raylib.IsKeyPressed(.RIGHT) {
		return true
	}
	return gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .LEFT_FACE_RIGHT)
}

@(private = "file")
menu_accept_pressed :: proc() -> bool {
	if raylib.IsKeyPressed(.ENTER) || raylib.IsKeyPressed(.SPACE) {
		return true
	}
	return gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_FACE_DOWN)
}

@(private = "file")
menu_back_pressed :: proc() -> bool {
	if raylib.IsKeyPressed(.ESCAPE) || raylib.IsKeyPressed(.BACKSPACE) {
		return true
	}
	return gamepad_active() && raylib.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_FACE_RIGHT)
}

@(private = "file")
draw_menu_background :: proc(compact: bool) {
	raylib.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, MENU_BG)
	if compact {
		x := i32(164)
		y := i32(54)
		w := i32(312)
		h := i32(252)
		raylib.DrawRectangle(x, y, w, h, MENU_PANEL)
		raylib.DrawRectangleLines(x, y, w, h, MENU_PANEL_LINE)
		raylib.DrawRectangle(x + 10, y + 10, w - 20, 2, MENU_ACCENT)
		raylib.DrawRectangle(x + 10, y + h - 12, w - 20, 2, MENU_ACCENT)
	} else {
		raylib.DrawRectangle(32, 28, SCREEN_WIDTH - 64, SCREEN_HEIGHT - 56, MENU_PANEL)
		raylib.DrawRectangleLines(32, 28, SCREEN_WIDTH - 64, SCREEN_HEIGHT - 56, MENU_PANEL_LINE)
		raylib.DrawRectangle(42, 38, SCREEN_WIDTH - 84, 2, MENU_ACCENT)
		raylib.DrawRectangle(42, SCREEN_HEIGHT - 40, SCREEN_WIDTH - 84, 2, MENU_ACCENT)
	}
}

@(private = "file")
draw_main_menu :: proc(menu: ^Menu_State) {
	if menu_is_paused() {
		draw_text_centered("PAUSED", SCREEN_WIDTH / 2, 82, 26, MENU_ACCENT)
		draw_text_centered("Esc / Start to resume", SCREEN_WIDTH / 2, 112, 10, MENU_MUTED)

		labels := [?]string{"RESUME", "OPTIONS", "CONTROLS", "QUIT"}
		for label, i in labels {
			draw_menu_button(pause_button_rect(i), label, menu.selected == i)
		}
	} else {
		draw_text_centered("THE WATCHERS", SCREEN_WIDTH / 2, 66, 34, MENU_ACCENT)
		draw_text_centered("WASD / Arrows / Gamepad to choose", SCREEN_WIDTH / 2, 104, 10, MENU_MUTED)

		labels := [?]string{"PLAY", "OPTIONS", "CONTROLS", "QUIT"}
		for label, i in labels {
			draw_menu_button(main_button_rect(i), label, menu.selected == i)
		}
	}
}

@(private = "file")
draw_options_menu :: proc(menu: ^Menu_State) {
	draw_text_centered("OPTIONS", SCREEN_WIDTH / 2, 62, 28, MENU_ACCENT)
	draw_option_slider(menu, 0, "MUSIC", menu.music_volume)
	draw_option_slider(menu, 1, "SFX", menu.sfx_volume)

	hints_text := "HINTS: ON"
	if !menu.hints_enabled {
		hints_text = "HINTS: OFF"
	}
	draw_menu_button(options_row_rect(2), hints_text, menu.selected == 2)
	draw_menu_button(options_row_rect(3), "BACK", menu.selected == 3)
}

@(private = "file")
draw_controls_menu :: proc(menu: ^Menu_State) {
	draw_text_centered("CONTROLS", SCREEN_WIDTH / 2, 62, 28, MENU_ACCENT)

	y := 108
	if menu.input_mode == .Gamepad {
		draw_text_centered("GAMEPAD", SCREEN_WIDTH / 2, y, 16, MENU_ACCENT)
		draw_control_line("Move", "Left Stick / D-Pad", y + 32)
		draw_control_line("Jump", "A", y + 52)
		draw_control_line("Attack", "X", y + 72)
		draw_control_line("Aim", "Left Trigger", y + 92)
		draw_control_line("Cycle Target", "Right Bumper", y + 112)
		draw_control_line("Spear / Recall", "Y", y + 132)
		draw_control_line("Teleport", "B", y + 152)
	} else {
		draw_text_centered("KEYBOARD", SCREEN_WIDTH / 2, y, 16, MENU_ACCENT)
		draw_control_line("Move", "A / D or Arrows", y + 32)
		draw_control_line("Jump", "W / Up / Space", y + 52)
		draw_control_line("Attack", "J", y + 72)
		draw_control_line("Aim", "Hold K", y + 92)
		draw_control_line("Cycle Target", "H", y + 112)
		draw_control_line("Spear / Recall", "L", y + 132)
		draw_control_line("Teleport", "I", y + 152)
	}

	draw_menu_button(controls_back_rect(), "BACK", true)
}

@(private = "file")
draw_option_slider :: proc(menu: ^Menu_State, index: int, label: string, value: f32) {
	row := options_row_rect(index)
	selected := menu.selected == index
	color := MENU_BUTTON
	if selected {
		color = MENU_BUTTON_HOVER
	}
	raylib.DrawRectangleRec(row, color)
	raylib.DrawRectangleLines(i32(row.x), i32(row.y), i32(row.width), i32(row.height), MENU_PANEL_LINE)
	draw_text(label, int(row.x) + 14, int(row.y) + 10, 14, MENU_ACCENT)

	track := slider_rect()
	track.y = row.y + row.height / 2 - MENU_SLIDER_H / 2
	raylib.DrawRectangleRec(track, MENU_DARK)
	fill := track
	fill.width = track.width * clamp01(value)
	raylib.DrawRectangleRec(fill, MENU_ACCENT)
	knob_x := track.x + track.width * clamp01(value) - 3
	raylib.DrawRectangle(i32(knob_x), i32(track.y) - 5, 6, 18, MENU_ACCENT)

	percent := fmt.tprintf("%3d%%", int(clamp01(value) * 100 + 0.5))
	draw_text(percent, int(row.x + row.width) - 54, int(row.y) + 10, 12, MENU_MUTED)
}

@(private = "file")
draw_menu_button :: proc(rect: raylib.Rectangle, label: string, selected: bool) {
	color := MENU_BUTTON
	text_color := MENU_ACCENT
	if selected {
		color = MENU_BUTTON_HOVER
		text_color = raylib.WHITE
	}
	raylib.DrawRectangleRec(rect, color)
	raylib.DrawRectangleLines(i32(rect.x), i32(rect.y), i32(rect.width), i32(rect.height), MENU_PANEL_LINE)
	draw_text_centered_in_rect(label, rect, 18, text_color)
}

@(private = "file")
draw_control_line :: proc(action, binding: string, y: int) {
	draw_text(action, 180, y, 12, MENU_MUTED)
	draw_text(binding, 330, y, 12, MENU_ACCENT)
}

@(private = "file")
draw_text :: proc(text: string, x, y, size: int, color: raylib.Color) {
	cstr := strings.clone_to_cstring(text, context.temp_allocator)
	raylib.DrawText(cstr, i32(x), i32(y), i32(size), color)
}

@(private = "file")
draw_text_centered :: proc(text: string, x, y, size: int, color: raylib.Color) {
	cstr := strings.clone_to_cstring(text, context.temp_allocator)
	w := raylib.MeasureText(cstr, i32(size))
	raylib.DrawText(cstr, i32(x) - w / 2, i32(y), i32(size), color)
}

@(private = "file")
draw_text_centered_in_rect :: proc(text: string, rect: raylib.Rectangle, size: int, color: raylib.Color) {
	cstr := strings.clone_to_cstring(text, context.temp_allocator)
	w := raylib.MeasureText(cstr, i32(size))
	x := i32(rect.x + rect.width / 2) - w / 2
	y := i32(rect.y + rect.height / 2) - i32(size) / 2
	raylib.DrawText(cstr, x, y, i32(size), color)
}

@(private = "file")
main_button_rect :: proc(index: int) -> raylib.Rectangle {
	return {MENU_BUTTON_X, MENU_MAIN_BUTTON_Y + f32(index) * MENU_ROW_GAP, MENU_BUTTON_W, MENU_BUTTON_H}
}

@(private = "file")
pause_button_rect :: proc(index: int) -> raylib.Rectangle {
	return {232, 136 + f32(index) * 38, 176, 30}
}

@(private = "file")
options_row_rect :: proc(index: int) -> raylib.Rectangle {
	return {MENU_OPTIONS_X, MENU_OPTIONS_Y + f32(index) * MENU_ROW_GAP, MENU_OPTIONS_W, MENU_BUTTON_H}
}

@(private = "file")
controls_back_rect :: proc() -> raylib.Rectangle {
	return {MENU_BUTTON_X, 302, MENU_BUTTON_W, MENU_BUTTON_H}
}

@(private = "file")
slider_rect :: proc() -> raylib.Rectangle {
	return {MENU_SLIDER_X, 0, MENU_SLIDER_W, MENU_SLIDER_H}
}

@(private = "file")
slider_value_from_mouse :: proc(mouse: raylib.Vector2) -> f32 {
	return clamp01((mouse.x - MENU_SLIDER_X) / MENU_SLIDER_W)
}

clamp01 :: proc(value: f32) -> f32 {
	if value < 0 {
		return 0
	}
	if value > 1 {
		return 1
	}
	return value
}

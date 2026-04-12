package game

import "vendor:raylib"
import "core:fmt"
import "core:strings"

Hint_Id :: enum {
	Summon_Spear,
	Throw_Spear,
	Teleport,
	Sign_Target,
	Count,
}

HINT_COUNT :: int(Hint_Id.Count)

Hint_Events :: struct {
	spear_summoned: bool,
	spear_thrown:   bool,
	teleported:     bool,
	sign_used:      bool,
}

Hints_State :: struct {
	completed: [HINT_COUNT]bool,
	current:   Hint_Id,
	has_hint:  bool,
}

HINT_BOX_BG :: raylib.Color{0x08, 0x06, 0x0a, 0xc8}
HINT_BOX_LINE :: raylib.Color{0xd8, 0xd1, 0xbc, 0xd8}
HINT_TEXT :: raylib.Color{0xf2, 0xed, 0xdc, 0xff}
HINT_LABEL :: raylib.Color{0xd8, 0xd1, 0xbc, 0xff}

init_hints :: proc(hints: ^Hints_State) {
	hints.current = .Summon_Spear
	hints.has_hint = true
	for i in 0 ..< HINT_COUNT {
		hints.completed[i] = false
	}
}

update_hints :: proc(
	hints: ^Hints_State,
	events: Hint_Events,
	player: ^Player,
	enemies: ^[MAX_ENEMIES]Enemy,
	enemy_count: int,
	signs: ^[MAX_DECORATIVE_SIGNS]Decorative_Sign,
	sign_count: int,
	camera: raylib.Camera2D,
) {
	if events.spear_summoned {
		hints.completed[int(Hint_Id.Summon_Spear)] = true
	}
	if events.spear_thrown {
		hints.completed[int(Hint_Id.Throw_Spear)] = true
	}
	if events.teleported {
		hints.completed[int(Hint_Id.Teleport)] = true
	}
	if events.sign_used {
		hints.completed[int(Hint_Id.Sign_Target)] = true
	}

	hints.has_hint = false
	if !hints.completed[int(Hint_Id.Summon_Spear)] {
		hints.current = .Summon_Spear
		hints.has_hint = true
		return
	}
	if !hints.completed[int(Hint_Id.Throw_Spear)] && enemy_in_hint_range(player, enemies, enemy_count) {
		hints.current = .Throw_Spear
		hints.has_hint = true
		return
	}
	if hints.completed[int(Hint_Id.Throw_Spear)] && !hints.completed[int(Hint_Id.Teleport)] {
		hints.current = .Teleport
		hints.has_hint = true
		return
	}
	if hints.completed[int(Hint_Id.Teleport)] &&
		!hints.completed[int(Hint_Id.Sign_Target)] &&
		sign_in_view(signs, sign_count, camera) {
		hints.current = .Sign_Target
		hints.has_hint = true
		return
	}
}

draw_hints :: proc(hints: ^Hints_State, input_mode: Menu_Input_Mode, enabled: bool) {
	if !enabled || !hints.has_hint {
		return
	}

	text := hint_text(hints.current, input_mode)
	box := raylib.Rectangle{54, 18, SCREEN_WIDTH - 108, 66}
	raylib.DrawRectangleRec(box, HINT_BOX_BG)
	raylib.DrawRectangleLinesEx(box, 1, HINT_BOX_LINE)
	draw_hint_text("HINT", int(box.x) + 10, int(box.y) + 8, 10, HINT_LABEL)
	draw_wrapped_hint_text(text, int(box.x) + 10, int(box.y) + 25, int(box.width) - 20, 10, 14, HINT_TEXT)
}

@(private = "file")
hint_text :: proc(id: Hint_Id, input_mode: Menu_Input_Mode) -> string {
	summon := "L"
	throw := "J"
	teleport := "I"
	if input_mode == .Gamepad {
		summon = "Y"
		throw = "X"
		teleport = "B"
	}

	switch id {
	case .Summon_Spear:
		return fmt.tprintf("Press %s to summon your weapon.", summon)
	case .Throw_Spear:
		return fmt.tprintf("Press %s to throw your weapon at an enemy. It will automatically target the closest foe.", throw)
	case .Teleport:
		return fmt.tprintf("Press %s and then %s to transmit your body to your weapon's location. Slam into a foe for heavy damage.", throw, teleport)
	case .Sign_Target:
		return "Your weapon can target certain objects too. This allows you to teleport through platforms. Try it on that sign."
	case .Count:
		return ""
	}
	return ""
}

@(private = "file")
enemy_in_hint_range :: proc(player: ^Player, enemies: ^[MAX_ENEMIES]Enemy, enemy_count: int) -> bool {
	range_sq := f32(COMBAT_RANGE * COMBAT_RANGE)
	for i in 0 ..< enemy_count {
		e := &enemies[i]
		if e.state == .Inactive || e.state == .Dead {
			continue
		}
		center := get_enemy_center(e)
		dx := center.x - player.pos.x
		dy := center.y - player.pos.y
		if dx * dx + dy * dy <= range_sq {
			return true
		}
	}
	return false
}

@(private = "file")
sign_in_view :: proc(signs: ^[MAX_DECORATIVE_SIGNS]Decorative_Sign, sign_count: int, camera: raylib.Camera2D) -> bool {
	half_w := f32(SCREEN_WIDTH) / (2 * camera.zoom)
	half_h := f32(SCREEN_HEIGHT) / (2 * camera.zoom)
	for i in 0 ..< sign_count {
		sign := &signs[i]
		if !sign.active {
			continue
		}
		center := get_decorative_sign_center(sign)
		if center.x >= camera.target.x - half_w &&
			center.x <= camera.target.x + half_w &&
			center.y >= camera.target.y - half_h &&
			center.y <= camera.target.y + half_h {
			return true
		}
	}
	return false
}

@(private = "file")
draw_wrapped_hint_text :: proc(text: string, x, y, max_width, size, line_height: int, color: raylib.Color) {
	line_start := 0
	line_end := 0
	word_start := 0
	cursor_y := y

	for i := 0; i <= len(text); i += 1 {
		at_end := i == len(text)
		if !at_end && text[i] != ' ' {
			continue
		}

		candidate_end := i
		if line_start == line_end {
			candidate := text[line_start:candidate_end]
			if hint_text_width(candidate, size) > max_width && word_start > line_start {
				draw_hint_text(text[line_start:word_start], x, cursor_y, size, color)
				cursor_y += line_height
				line_start = word_start + 1
			}
		} else {
			candidate := text[line_start:candidate_end]
			if hint_text_width(candidate, size) > max_width {
				draw_hint_text(text[line_start:line_end], x, cursor_y, size, color)
				cursor_y += line_height
				line_start = word_start
			}
		}

		line_end = candidate_end
		word_start = i + 1
	}

	if line_start < len(text) {
		draw_hint_text(text[line_start:], x, cursor_y, size, color)
	}
}

@(private = "file")
hint_text_width :: proc(text: string, size: int) -> int {
	cstr := strings.clone_to_cstring(text, context.temp_allocator)
	return int(raylib.MeasureText(cstr, i32(size)))
}

@(private = "file")
draw_hint_text :: proc(text: string, x, y, size: int, color: raylib.Color) {
	cstr := strings.clone_to_cstring(text, context.temp_allocator)
	raylib.DrawText(cstr, i32(x), i32(y), i32(size), color)
}

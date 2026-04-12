package game

import "vendor:raylib"
import "core:fmt"
import "core:strings"

HP_BAR_COLOR         :: raylib.Color{0xf0, 0x21, 0x58, 0xff}
HP_BAR_BG_COLOR      :: raylib.Color{0x30, 0x10, 0x18, 0xff}
HP_BAR_OUTLINE_COLOR :: raylib.Color{0x00, 0x00, 0x00, 0xff}

draw_hud :: proc(p: ^Player, cherub_souls: int) {
	souls_text := fmt.tprintf("CHERUB SOULS: %d", cherub_souls)
	souls_cstr := strings.clone_to_cstring(souls_text, context.temp_allocator)
	raylib.DrawText(souls_cstr, 8, 8, 10, raylib.WHITE)

	// Outline
	raylib.DrawRectangle(
		HP_BAR_X - HP_BAR_OUTLINE,
		HP_BAR_Y - HP_BAR_OUTLINE,
		HP_BAR_W + HP_BAR_OUTLINE * 2,
		HP_BAR_H + HP_BAR_OUTLINE * 2,
		HP_BAR_OUTLINE_COLOR,
	)

	// Background (empty portion)
	raylib.DrawRectangle(HP_BAR_X, HP_BAR_Y, HP_BAR_W, HP_BAR_H, HP_BAR_BG_COLOR)

	// Fill based on current HP
	fill_w := i32(f32(HP_BAR_W) * f32(p.hp) / f32(PLAYER_MAX_HP))
	if fill_w > 0 {
		raylib.DrawRectangle(HP_BAR_X, HP_BAR_Y, fill_w, HP_BAR_H, HP_BAR_COLOR)
	}
}

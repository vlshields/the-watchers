package game

import "vendor:raylib"
import "core:fmt"
import "core:strings"

draw_hud :: proc(p: ^Player, cherub_souls: int) {
	raylib.DrawRectangle(HUD_TEXT_BG_X, HUD_TEXT_BG_Y, HUD_TEXT_BG_W, HUD_TEXT_BG_H, HUD_TEXT_BG_COLOR)

	souls_text := fmt.tprintf("CHERUB SOULS: %d", cherub_souls)
	souls_cstr := strings.clone_to_cstring(souls_text, context.temp_allocator)
	raylib.DrawText(souls_cstr, 8, 8, 10, raylib.WHITE)

	potions_text := fmt.tprintf("HP POTIONS: %d", p.hp_potions)
	potions_cstr := strings.clone_to_cstring(potions_text, context.temp_allocator)
	raylib.DrawText(potions_cstr, 8, 20, 10, raylib.WHITE)

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

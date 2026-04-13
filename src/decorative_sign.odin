package game

import "vendor:raylib"
import dm "../dotmap"

Decorative_Sign :: struct {
	active: bool,
	pos:    raylib.Vector2,
}

@(private = "file")
decorative_sign_tex: raylib.Texture2D

init_decorative_signs :: proc(
	signs: ^[MAX_DECORATIVE_SIGNS]Decorative_Sign,
	count: ^int,
	map_data: ^dm.Dot_Map,
) {
	decorative_sign_tex = raylib.LoadTexture("assets/sprites/decorative_sign.png")

	count^ = 0
	for row, ry in map_data.grid {
		for cell, cx in row {
			if cell.symbol != '@' || count^ >= MAX_DECORATIVE_SIGNS {
				continue
			}

			td, has_meta := map_data.metadata['@']
			if !has_meta {
				continue
			}

			spawn_key := dm.extract_kv(td.other, "spawn_point")
			can_target := dm.extract_kv(td.other, "spear_can_target")
			if spawn_key == "decorative_sign" && can_target == "true" {
				sign := &signs[count^]
				sign.active = true
				sign.pos = {
					f32(cx) * TILE_SIZE + TILE_SIZE / 2,
					f32(ry) * TILE_SIZE + TILE_SIZE,
				}
				count^ += 1
			}
			delete(spawn_key)
			delete(can_target)
		}
	}
}

unload_decorative_signs :: proc() {
	raylib.UnloadTexture(decorative_sign_tex)
}

update_decorative_signs :: proc(
	signs: ^[MAX_DECORATIVE_SIGNS]Decorative_Sign,
	count: int,
	player: ^Player,
) {
	// Respawn signs when the player falls below the platform they sit on,
	// so they can't get locked out of areas only reachable via spear teleport.
	for i in 0 ..< count {
		sign := &signs[i]
		if sign.active {
			continue
		}
		if player.pos.y > sign.pos.y {
			sign.active = true
		}
	}
}

draw_decorative_signs :: proc(signs: ^[MAX_DECORATIVE_SIGNS]Decorative_Sign, count: int) {
	for i in 0 ..< count {
		sign := &signs[i]
		if !sign.active {
			continue
		}

		raylib.DrawTexture(
			decorative_sign_tex,
			i32(sign.pos.x - f32(SPRITE_DST_SIZE) / 2),
			i32(sign.pos.y - f32(SPRITE_DST_SIZE)),
			raylib.WHITE,
		)
	}
}

get_decorative_sign_center :: proc(sign: ^Decorative_Sign) -> raylib.Vector2 {
	return {sign.pos.x, sign.pos.y - f32(SPRITE_DST_SIZE) / 2}
}

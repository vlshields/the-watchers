package game

import "vendor:raylib"
import dm "../dotmap"

Enemy_State :: enum {
	Inactive,
	Patrol,
	Hit,
	Dead,
}

Enemy :: struct {
	state:         Enemy_State,
	pos:           raylib.Vector2,
	spawn_pos:     raylib.Vector2,
	hp:            int,
	facing_left:   bool,
	current_frame: f32,
	anim_timer:    f32,
	hit_timer:     f32,
	dead_timer:    f32,
}

@(private = "file")
cherub_idle_tex: raylib.Texture2D
@(private = "file")
cherub_move_tex: raylib.Texture2D
@(private = "file")
cherub_idle_frames: int
@(private = "file")
cherub_move_frames: int

init_enemies :: proc(enemies: ^[MAX_ENEMIES]Enemy, count: ^int, map_data: ^dm.Dot_Map) {
	cherub_idle_tex = raylib.LoadTexture("assets/sprites/enemy_cherub_idle.png")
	cherub_move_tex = raylib.LoadTexture("assets/sprites/enemy_cherub_move.png")
	cherub_idle_frames = int(cherub_idle_tex.width) / SPRITE_SRC_SIZE
	cherub_move_frames = int(cherub_move_tex.width) / SPRITE_SRC_SIZE

	count^ = 0
	for row, ry in map_data.grid {
		for cell, cx in row {
			if cell.symbol == 'c' {
				td, has_meta := map_data.metadata['c']
				if has_meta {
					spawn_key := dm.extract_kv(td.other, "spawn_point")
					if spawn_key == "enemy_cherub" && count^ < MAX_ENEMIES {
						e := &enemies[count^]
						e.state = .Patrol
						e.pos = {f32(cx) * TILE_SIZE + TILE_SIZE / 2, f32(ry) * TILE_SIZE}
						e.spawn_pos = e.pos
						e.hp = ENEMY_CHERUB_HP
						e.facing_left = false
						e.current_frame = 0
						e.anim_timer = 0
						e.hit_timer = 0
						e.dead_timer = 0
						count^ += 1
					}
					delete(spawn_key)
				}
			}
		}
	}
}

unload_enemies :: proc() {
	raylib.UnloadTexture(cherub_idle_tex)
	raylib.UnloadTexture(cherub_move_tex)
}

update_enemies :: proc(enemies: ^[MAX_ENEMIES]Enemy, count: int, dt: f32) {
	for i in 0 ..< count {
		update_enemy(&enemies[i], dt)
	}
}

draw_enemies :: proc(enemies: ^[MAX_ENEMIES]Enemy, count: int) {
	for i in 0 ..< count {
		draw_enemy(&enemies[i])
	}
}

get_enemy_center :: proc(e: ^Enemy) -> raylib.Vector2 {
	return {e.pos.x, e.pos.y - f32(ENEMY_CHERUB_HITBOX_H) / 2}
}

enemy_take_damage :: proc(e: ^Enemy, damage: int) {
	if e.state == .Inactive || e.state == .Dead {
		return
	}
	e.hp -= damage
	e.state = .Hit
	e.hit_timer = 0.3
	e.current_frame = 0
	e.anim_timer = 0
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

@(private = "file")
update_enemy :: proc(e: ^Enemy, dt: f32) {
	switch e.state {
	case .Inactive:
		return
	case .Dead:
		e.dead_timer -= dt
		if e.dead_timer <= 0 {
			e.state = .Inactive
		}
	case .Hit:
		e.hit_timer -= dt
		if e.hit_timer <= 0 {
			if e.hp <= 0 {
				e.state = .Dead
				e.dead_timer = 0.3
			} else {
				e.state = .Patrol
			}
			e.current_frame = 0
			e.anim_timer = 0
		}
	case .Patrol:
		speed: f32 = e.facing_left ? -ENEMY_CHERUB_SPEED : ENEMY_CHERUB_SPEED
		e.pos.x += speed * dt

		if abs(e.pos.x - e.spawn_pos.x) > ENEMY_CHERUB_PATROL_DIST {
			e.facing_left = !e.facing_left
			if e.pos.x > e.spawn_pos.x + ENEMY_CHERUB_PATROL_DIST {
				e.pos.x = e.spawn_pos.x + ENEMY_CHERUB_PATROL_DIST
			} else if e.pos.x < e.spawn_pos.x - ENEMY_CHERUB_PATROL_DIST {
				e.pos.x = e.spawn_pos.x - ENEMY_CHERUB_PATROL_DIST
			}
		}

		if cherub_move_frames > 1 {
			e.anim_timer += dt
			if e.anim_timer >= ANIM_FRAME_TIME {
				e.anim_timer -= ANIM_FRAME_TIME
				e.current_frame += 1
				if int(e.current_frame) >= cherub_move_frames {
					e.current_frame = 0
				}
			}
		}
	}
}

@(private = "file")
draw_enemy :: proc(e: ^Enemy) {
	if e.state == .Inactive {
		return
	}

	tex: raylib.Texture2D
	frames: int
	switch e.state {
	case .Patrol:
		tex = cherub_move_tex
		frames = cherub_move_frames
	case .Hit:
		tex = cherub_idle_tex
		frames = cherub_idle_frames
	case .Dead:
		tex = cherub_idle_tex
		frames = cherub_idle_frames
	case .Inactive:
		return
	}

	frame := int(e.current_frame)
	if frame >= frames {
		frame = frames - 1
	}

	src := raylib.Rectangle{
		f32(frame * SPRITE_SRC_SIZE), 0,
		e.facing_left ? -f32(SPRITE_SRC_SIZE) : f32(SPRITE_SRC_SIZE),
		f32(SPRITE_SRC_SIZE),
	}
	dst := raylib.Rectangle{
		e.pos.x - SPRITE_DST_SIZE / 2,
		e.pos.y - SPRITE_DST_SIZE,
		SPRITE_DST_SIZE,
		SPRITE_DST_SIZE,
	}

	tint := raylib.WHITE
	if e.state == .Hit {
		flash := int(e.hit_timer / 0.05) % 2
		if flash == 0 {
			tint = raylib.Color{255, 100, 100, 255}
		}
	} else if e.state == .Dead {
		alpha := u8(255 * (e.dead_timer / 0.3))
		tint = raylib.Color{255, 255, 255, alpha}
	}

	raylib.DrawTexturePro(tex, src, dst, {0, 0}, 0, tint)
}

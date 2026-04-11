package game

import "vendor:raylib"
import dm "../dotmap"

Player :: struct {
	pos:               raylib.Vector2, // bottom-center
	vel:               raylib.Vector2,
	hp:                int,
	on_ground:         bool,
	jumps_left:        int,
	facing_left:       bool,
	moving:            bool,
	is_throwing:       bool,
	move_tex:          raylib.Texture2D,
	idle_tex:          raylib.Texture2D,
	jump_tex:          raylib.Texture2D,
	fall_tex:          raylib.Texture2D,
	throw_tex:         raylib.Texture2D,
	frame_count:       int,
	idle_frames:       int,
	jump_frames:       int,
	fall_frames:       int,
	current_frame:     f32,
	anim_timer:        f32,
	hit_timer:         f32,
	teleport_invuln_timer: f32,
}

init_player :: proc(p: ^Player, spawn: raylib.Vector2) {
	p.pos = spawn
	p.vel = {}
	p.hp = PLAYER_MAX_HP
	p.on_ground = false
	p.jumps_left = MAX_JUMPS
	p.facing_left = false
	p.moving = false
	p.current_frame = 0
	p.anim_timer = 0
	p.teleport_invuln_timer = 0

	p.move_tex = raylib.LoadTexture("assets/sprites/player_move.png")
	p.idle_tex = raylib.LoadTexture("assets/sprites/player_idle.png")
	p.jump_tex = raylib.LoadTexture("assets/sprites/player_jump.png")
	p.fall_tex = raylib.LoadTexture("assets/sprites/player_falling.png")
	p.throw_tex = raylib.LoadTexture("assets/sprites/player_throws_spear.png")
	p.frame_count = int(p.move_tex.width) / SPRITE_SRC_SIZE
	p.idle_frames = int(p.idle_tex.width) / SPRITE_SRC_SIZE
	p.jump_frames = int(p.jump_tex.width) / SPRITE_SRC_SIZE
	p.fall_frames = int(p.fall_tex.width) / SPRITE_SRC_SIZE
}

unload_player :: proc(p: ^Player) {
	raylib.UnloadTexture(p.move_tex)
	raylib.UnloadTexture(p.idle_tex)
	raylib.UnloadTexture(p.jump_tex)
	raylib.UnloadTexture(p.fall_tex)
	raylib.UnloadTexture(p.throw_tex)
}

player_take_damage :: proc(p: ^Player, damage: int) {
	if p.teleport_invuln_timer > 0 {
		return
	}

	p.hp -= damage
	if p.hp < 0 {
		p.hp = 0
	}
	p.hit_timer = PLAYER_HIT_FLASH_DURATION
}

update_player :: proc(p: ^Player, map_data: ^dm.Dot_Map, dt: f32) {
	if p.hit_timer > 0 {
		p.hit_timer -= dt
	}
	if p.teleport_invuln_timer > 0 {
		p.teleport_invuln_timer -= dt
	}

	was_on_ground := p.on_ground
	was_rising := p.vel.y < 0

	// Horizontal input
	move_x: f32 = 0
	if input_move_left() {
		move_x -= 1
	}
	if input_move_right() {
		move_x += 1
	}
	p.vel.x = move_x * PLAYER_SPEED

	// Jump (double jump)
	if p.jumps_left > 0 && input_jump() {
		p.vel.y = JUMP_VELOCITY
		p.on_ground = false
		p.jumps_left -= 1
	}

	// Gravity
	p.vel.y += GRAVITY * dt
	if p.vel.y > MAX_FALL_SPEED {
		p.vel.y = MAX_FALL_SPEED
	}

	move_and_collide(p, map_data, dt)

	// Facing
	was_moving := p.moving
	p.moving = move_x != 0
	if move_x < 0 {
		p.facing_left = true
	} else if move_x > 0 {
		p.facing_left = false
	}

	// Animation state transitions
	rising := p.vel.y < 0
	anim_changed := (p.moving != was_moving) ||
		(p.on_ground != was_on_ground) ||
		(!p.on_ground && rising != was_rising)
	if anim_changed {
		p.current_frame = 0
		p.anim_timer = 0
	}

	if p.on_ground {
		frames := p.moving ? p.frame_count : p.idle_frames
		frame_time: f32 = p.moving ? ANIM_FRAME_TIME : ANIM_PLAYER_IDLE_TIME
		if frames > 1 {
			p.anim_timer += dt
			if p.anim_timer >= frame_time {
				p.anim_timer -= frame_time
				p.current_frame += 1
				if int(p.current_frame) >= frames {
					p.current_frame = 0
				}
			}
		}
	} else {
		frames := rising ? p.jump_frames : p.fall_frames
		if frames > 1 {
			p.anim_timer += dt
			if p.anim_timer >= ANIM_FRAME_TIME {
				p.anim_timer -= ANIM_FRAME_TIME
				p.current_frame += 1
				if int(p.current_frame) >= frames {
					p.current_frame = f32(frames - 1)
				}
			}
		}
	}
}

draw_player :: proc(p: ^Player) {
	tex: raylib.Texture2D

	if p.is_throwing {
		tex = p.throw_tex
	} else if !p.on_ground {
		tex = (p.vel.y < 0) ? p.jump_tex : p.fall_tex
	} else if p.moving {
		tex = p.move_tex
	} else {
		tex = p.idle_tex
	}

	frame := int(p.current_frame)
	src := raylib.Rectangle{
		f32(frame * SPRITE_SRC_SIZE), 0,
		p.facing_left ? -f32(SPRITE_SRC_SIZE) : f32(SPRITE_SRC_SIZE),
		f32(SPRITE_SRC_SIZE),
	}
	dst := raylib.Rectangle{
		p.pos.x - SPRITE_DST_SIZE / 2,
		p.pos.y - SPRITE_DST_SIZE,
		SPRITE_DST_SIZE,
		SPRITE_DST_SIZE,
	}
	raylib.DrawTexturePro(tex, src, dst, {0, 0}, 0, raylib.WHITE)
}

// ---------------------------------------------------------------------------
// Collision
// ---------------------------------------------------------------------------

get_hitbox :: proc(p: ^Player) -> raylib.Rectangle {
	return {
		p.pos.x - f32(PLAYER_HITBOX_W) / 2,
		p.pos.y - f32(PLAYER_HITBOX_H),
		f32(PLAYER_HITBOX_W),
		f32(PLAYER_HITBOX_H),
	}
}

is_solid :: proc(map_data: ^dm.Dot_Map, tx, ty: int) -> bool {
	if ty < 0 || ty >= len(map_data.grid) {
		return true
	}
	row := map_data.grid[ty]
	if tx < 0 || tx >= len(row) {
		return true
	}
	sym := row[tx].symbol
	td, has := map_data.metadata[sym]
	if !has {
		return false
	}
	return !td.passable && len(td.tiles) > 0
}

check_rect_solid :: proc(map_data: ^dm.Dot_Map, rect: raylib.Rectangle) -> bool {
	x0 := int(rect.x) / TILE_SIZE
	y0 := int(rect.y) / TILE_SIZE
	x1 := int(rect.x + rect.width - 0.01) / TILE_SIZE
	y1 := int(rect.y + rect.height - 0.01) / TILE_SIZE

	for ty in y0 ..= y1 {
		for tx in x0 ..= x1 {
			if is_solid(map_data, tx, ty) {
				return true
			}
		}
	}
	return false
}

move_and_collide :: proc(p: ^Player, map_data: ^dm.Dot_Map, dt: f32) {
	// Move X
	p.pos.x += p.vel.x * dt
	hb := get_hitbox(p)
	if check_rect_solid(map_data, hb) {
		if p.vel.x > 0 {
			tile_x := int(hb.x + hb.width) / TILE_SIZE
			p.pos.x = f32(tile_x * TILE_SIZE) - f32(PLAYER_HITBOX_W) / 2
		} else if p.vel.x < 0 {
			tile_x := int(hb.x) / TILE_SIZE
			p.pos.x = f32((tile_x + 1) * TILE_SIZE) + f32(PLAYER_HITBOX_W) / 2
		}
		p.vel.x = 0
	}

	// Move Y
	p.pos.y += p.vel.y * dt
	hb = get_hitbox(p)
	p.on_ground = false
	if check_rect_solid(map_data, hb) {
		if p.vel.y > 0 {
			tile_y := int(hb.y + hb.height) / TILE_SIZE
			p.pos.y = f32(tile_y * TILE_SIZE)
			p.on_ground = true
			p.jumps_left = MAX_JUMPS
		} else if p.vel.y < 0 {
			tile_y := int(hb.y) / TILE_SIZE
			p.pos.y = f32((tile_y + 1) * TILE_SIZE) + f32(PLAYER_HITBOX_H)
		}
		p.vel.y = 0
	}
}

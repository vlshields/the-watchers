package game

import "core:math"
import "core:math/rand"
import "vendor:raylib"
import dm "../dotmap"

Enemy_Type :: enum {
	Cherub,
	Ghoul,
}

Enemy_State :: enum {
	Inactive,
	Patrol,
	Chase,
	Attack,
	Hit,
	Dead,
}

Enemy :: struct {
	type:             Enemy_Type,
	state:            Enemy_State,
	pos:              raylib.Vector2,
	spawn_pos:        raylib.Vector2,
	hp:               int,
	facing_left:      bool,
	current_frame:    f32,
	anim_timer:       f32,
	hit_timer:        f32,
	dead_timer:       f32,
	vel_y:            f32,
	on_ground:        bool,
	attack_cooldown:  f32,
	attack_fired:     bool,
	aggroed:          bool,
	attack_fx_frame:  f32,
	attack_fx_timer:  f32,
	attack_fx_active: bool,
	attack_hit_player: bool,
}

@(private = "file")
cherub_idle_tex: raylib.Texture2D
@(private = "file")
cherub_move_tex: raylib.Texture2D
@(private = "file")
cherub_attack_tex: raylib.Texture2D
@(private = "file")
cherub_idle_frames: int
@(private = "file")
cherub_move_frames: int
@(private = "file")
cherub_attack_frames: int

@(private = "file")
ghoul_move_tex: raylib.Texture2D
@(private = "file")
ghoul_attack_tex: raylib.Texture2D
@(private = "file")
ghoul_move_frames: int
@(private = "file")
ghoul_attack_frames: int

@(private = "file")
ghoul_attack_fx_tex: raylib.Texture2D
@(private = "file")
ghoul_attack_fx_frames: int

init_enemies :: proc(enemies: ^[MAX_ENEMIES]Enemy, count: ^int, map_data: ^dm.Dot_Map) {
	cherub_idle_tex = raylib.LoadTexture("assets/sprites/enemy_cherub_idle.png")
	cherub_move_tex = raylib.LoadTexture("assets/sprites/enemy_cherub_move.png")
	cherub_attack_tex = raylib.LoadTexture("assets/sprites/enemy_cherub_attack.png")
	cherub_idle_frames = int(cherub_idle_tex.width) / SPRITE_SRC_SIZE
	cherub_move_frames = int(cherub_move_tex.width) / SPRITE_SRC_SIZE
	cherub_attack_frames = int(cherub_attack_tex.width) / SPRITE_SRC_SIZE

	ghoul_move_tex = raylib.LoadTexture("assets/sprites/enemy_ghoul_move.png")
	ghoul_attack_tex = raylib.LoadTexture("assets/sprites/enemy_ghoul_attack.png")
	ghoul_move_frames = int(ghoul_move_tex.width) / SPRITE_SRC_SIZE
	ghoul_attack_frames = int(ghoul_attack_tex.width) / SPRITE_SRC_SIZE

	ghoul_attack_fx_tex = raylib.LoadTexture("assets/sprites/enemy_ghoul_attack_fx.png")
	ghoul_attack_fx_frames = int(ghoul_attack_fx_tex.width) / GHOUL_FX_FRAME_SIZE

	count^ = 0
	for row, ry in map_data.grid {
		for cell, cx in row {
			if cell.symbol == 'c' {
				td, has_meta := map_data.metadata['c']
				if has_meta {
					spawn_key := dm.extract_kv(td.other, "spawn_point")
					if spawn_key == "enemy_cherub" && count^ < MAX_ENEMIES {
						e := &enemies[count^]
						e.type = .Cherub
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
			} else if cell.symbol == 'g' {
				td, has_meta := map_data.metadata['g']
				if has_meta {
					spawn_key := dm.extract_kv(td.other, "spawn_point")
					if spawn_key == "enemy_ghoul" && count^ < MAX_ENEMIES {
						e := &enemies[count^]
						e.type = .Ghoul
						e.state = .Patrol
						e.pos = {f32(cx) * TILE_SIZE + TILE_SIZE / 2, f32(ry) * TILE_SIZE}
						e.spawn_pos = e.pos
						e.hp = ENEMY_GHOUL_HP
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
	raylib.UnloadTexture(cherub_attack_tex)
	raylib.UnloadTexture(ghoul_move_tex)
	raylib.UnloadTexture(ghoul_attack_tex)
	raylib.UnloadTexture(ghoul_attack_fx_tex)
}

update_enemies :: proc(
	enemies: ^[MAX_ENEMIES]Enemy,
	count: int,
	map_data: ^dm.Dot_Map,
	player: ^Player,
	projectiles: ^[MAX_PSYCHIC_PROJECTILES]Psychic_Projectile,
	proj_count: ^int,
	dt: f32,
) {
	for i in 0 ..< count {
		update_enemy(&enemies[i], map_data, player, projectiles, proj_count, dt)
	}
}

draw_enemies :: proc(enemies: ^[MAX_ENEMIES]Enemy, count: int) {
	for i in 0 ..< count {
		draw_enemy(&enemies[i])
	}
}

get_enemy_hitbox :: proc(e: ^Enemy) -> raylib.Rectangle {
	hw, hh: f32
	switch e.type {
	case .Cherub:
		hw = f32(ENEMY_CHERUB_HITBOX_W)
		hh = f32(ENEMY_CHERUB_HITBOX_H)
	case .Ghoul:
		hw = f32(ENEMY_GHOUL_HITBOX_W)
		hh = f32(ENEMY_GHOUL_HITBOX_H)
	}
	return {e.pos.x - hw / 2, e.pos.y - hh, hw, hh}
}

get_enemy_center :: proc(e: ^Enemy) -> raylib.Vector2 {
	hh: f32
	switch e.type {
	case .Cherub:
		hh = f32(ENEMY_CHERUB_HITBOX_H)
	case .Ghoul:
		hh = f32(ENEMY_GHOUL_HITBOX_H)
	}
	return {e.pos.x, e.pos.y - hh / 2}
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
update_enemy :: proc(
	e: ^Enemy,
	map_data: ^dm.Dot_Map,
	player: ^Player,
	projectiles: ^[MAX_PSYCHIC_PROJECTILES]Psychic_Projectile,
	proj_count: ^int,
	dt: f32,
) {
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
			} else if e.aggroed {
				e.state = .Chase
			} else {
				e.state = .Patrol
			}
			e.current_frame = 0
			e.anim_timer = 0
		}
		enemy_apply_gravity(e, map_data, dt)
	case .Attack:
		e.anim_timer += dt
		if e.anim_timer >= ANIM_FRAME_TIME {
			e.anim_timer -= ANIM_FRAME_TIME
			e.current_frame += 1
		}

		switch e.type {
		case .Cherub:
			// Fire projectile on second-to-last frame
			if !e.attack_fired && int(e.current_frame) >= cherub_attack_frames - 1 {
				e.attack_fired = true
				if proj_count^ < MAX_PSYCHIC_PROJECTILES {
					center := get_enemy_center(e)
					dx := player.pos.x - center.x
					dy := player.pos.y - center.y
					dist := math.sqrt(dx * dx + dy * dy)
					if dist < 1 {
						dist = 1
					}

					travel_time := dist / PSYCHIC_SPEED
					vx := dx / travel_time
					vy := dy / travel_time - 0.5 * PSYCHIC_ARC_GRAVITY * travel_time

					spread := (dist / ENEMY_CHERUB_ATTACK_RANGE) * 40.0
					vx += rand.float32_range(-spread, spread)
					vy += rand.float32_range(-spread * 0.5, spread * 0.3)

					spawn_psychic_projectile(projectiles, proj_count, center, {vx, vy})
				}
			}
			if int(e.current_frame) >= cherub_attack_frames {
				e.state = .Patrol
				e.attack_cooldown = ENEMY_CHERUB_ATTACK_COOLDOWN
				e.current_frame = 0
				e.anim_timer = 0
			}
		case .Ghoul:
			// Hold on last attack frame while FX plays
			if int(e.current_frame) >= ghoul_attack_frames {
				e.current_frame = f32(ghoul_attack_frames - 1)
			}
			// Start FX on last attack frame
			if int(e.current_frame) >= ghoul_attack_frames - 1 && !e.attack_fx_active {
				e.attack_fx_active = true
				e.attack_fx_frame = 0
				e.attack_fx_timer = 0
			}
			// Update FX animation and check collision
			if e.attack_fx_active {
				e.attack_fx_timer += dt
				if e.attack_fx_timer >= ANIM_FRAME_TIME {
					e.attack_fx_timer -= ANIM_FRAME_TIME
					e.attack_fx_frame += 1
				}
				if !e.attack_hit_player && int(e.attack_fx_frame) < ghoul_attack_fx_frames {
					fx_rect := get_ghoul_fx_rect(e)
					player_hb := get_hitbox(player)
					if raylib.CheckCollisionRecs(fx_rect, player_hb) {
						player_take_damage(player, ENEMY_GHOUL_ATTACK_DAMAGE)
						e.attack_hit_player = true
					}
				}
				// End attack when FX finishes
				if int(e.attack_fx_frame) >= ghoul_attack_fx_frames {
					e.attack_fx_active = false
					e.state = .Chase
					e.current_frame = 0
					e.anim_timer = 0
				}
			}
		}
		enemy_apply_gravity(e, map_data, dt)
	case .Chase:
		// Ghoul-only: charge toward the player
		e.facing_left = player.pos.x < e.pos.x
		dx := player.pos.x - e.pos.x
		dist := abs(dx)

		if dist <= ENEMY_GHOUL_MELEE_RANGE {
			e.state = .Attack
			e.current_frame = 0
			e.anim_timer = 0
			e.attack_fired = false
			e.attack_fx_active = false
			e.attack_hit_player = false
		} else {
			speed: f32 = e.facing_left ? -ENEMY_GHOUL_CHARGE_SPEED : ENEMY_GHOUL_CHARGE_SPEED
			e.pos.x += speed * dt

			hb := get_enemy_hitbox(e)
			if check_rect_solid(map_data, hb) {
				if speed > 0 {
					tile_x := int(hb.x + hb.width) / TILE_SIZE
					e.pos.x = f32(tile_x * TILE_SIZE) - f32(ENEMY_GHOUL_HITBOX_W) / 2
				} else {
					tile_x := int(hb.x) / TILE_SIZE
					e.pos.x = f32((tile_x + 1) * TILE_SIZE) + f32(ENEMY_GHOUL_HITBOX_W) / 2
				}
			}
		}

		if ghoul_move_frames > 1 {
			e.anim_timer += dt
			if e.anim_timer >= ANIM_FRAME_TIME {
				e.anim_timer -= ANIM_FRAME_TIME
				e.current_frame += 1
				if int(e.current_frame) >= ghoul_move_frames {
					e.current_frame = 0
				}
			}
		}
		enemy_apply_gravity(e, map_data, dt)
	case .Patrol:
		// Type-specific patrol parameters
		patrol_speed, patrol_dist, attack_range: f32
		move_frames: int
		half_hw: f32
		switch e.type {
		case .Cherub:
			patrol_speed = ENEMY_CHERUB_SPEED
			patrol_dist = ENEMY_CHERUB_PATROL_DIST
			attack_range = ENEMY_CHERUB_ATTACK_RANGE
			move_frames = cherub_move_frames
			half_hw = f32(ENEMY_CHERUB_HITBOX_W) / 2
		case .Ghoul:
			patrol_speed = ENEMY_GHOUL_SPEED
			patrol_dist = ENEMY_GHOUL_PATROL_DIST
			attack_range = 0
			move_frames = ghoul_move_frames
			half_hw = f32(ENEMY_GHOUL_HITBOX_W) / 2
		}

		// Ghoul aggro: triggered once when player is in viewport and on same platform
		if e.type == .Ghoul && !e.aggroed && e.on_ground && player.on_ground {
			cam_half_w := f32(SCREEN_WIDTH) / (2 * CAMERA_ZOOM)
			cam_half_h := f32(SCREEN_HEIGHT) / (2 * CAMERA_ZOOM)
			in_viewport := abs(e.pos.x - player.pos.x) <= cam_half_w && abs(e.pos.y - player.pos.y) <= cam_half_h
			same_platform := abs(e.pos.y - player.pos.y) < f32(TILE_SIZE)
			if in_viewport && same_platform {
				e.aggroed = true
				e.state = .Chase
				e.current_frame = 0
				e.anim_timer = 0
				enemy_apply_gravity(e, map_data, dt)
				return
			}
		}

		// Check if player is in range — if so, face them and attack immediately
		center := get_enemy_center(e)
		cdx := player.pos.x - center.x
		cdy := player.pos.y - center.y
		dist_sq := cdx * cdx + cdy * cdy
		in_range := attack_range > 0 && dist_sq <= attack_range * attack_range

		if in_range {
			e.facing_left = cdx < 0
			e.attack_cooldown -= dt
			if e.attack_cooldown <= 0 {
				e.state = .Attack
				e.current_frame = 0
				e.anim_timer = 0
				e.attack_fired = false
				enemy_apply_gravity(e, map_data, dt)
				return
			}
			enemy_apply_gravity(e, map_data, dt)
		} else {
			speed: f32 = e.facing_left ? -patrol_speed : patrol_speed
			e.pos.x += speed * dt

			hb := get_enemy_hitbox(e)
			if check_rect_solid(map_data, hb) {
				if speed > 0 {
					tile_x := int(hb.x + hb.width) / TILE_SIZE
					e.pos.x = f32(tile_x * TILE_SIZE) - half_hw
				} else {
					tile_x := int(hb.x) / TILE_SIZE
					e.pos.x = f32((tile_x + 1) * TILE_SIZE) + half_hw
				}
				e.facing_left = !e.facing_left
			}

			if abs(e.pos.x - e.spawn_pos.x) > patrol_dist {
				e.facing_left = !e.facing_left
				if e.pos.x > e.spawn_pos.x + patrol_dist {
					e.pos.x = e.spawn_pos.x + patrol_dist
				} else if e.pos.x < e.spawn_pos.x - patrol_dist {
					e.pos.x = e.spawn_pos.x - patrol_dist
				}
			}

			enemy_apply_gravity(e, map_data, dt)

			if move_frames > 1 {
				e.anim_timer += dt
				if e.anim_timer >= ANIM_FRAME_TIME {
					e.anim_timer -= ANIM_FRAME_TIME
					e.current_frame += 1
					if int(e.current_frame) >= move_frames {
						e.current_frame = 0
					}
				}
			}
		}
	}
}

@(private = "file")
enemy_apply_gravity :: proc(e: ^Enemy, map_data: ^dm.Dot_Map, dt: f32) {
	e.vel_y += GRAVITY * dt
	if e.vel_y > MAX_FALL_SPEED {
		e.vel_y = MAX_FALL_SPEED
	}
	e.pos.y += e.vel_y * dt

	hb := get_enemy_hitbox(e)
	e.on_ground = false
	if check_rect_solid(map_data, hb) {
		if e.vel_y > 0 {
			tile_y := int(hb.y + hb.height) / TILE_SIZE
			e.pos.y = f32(tile_y * TILE_SIZE)
			e.on_ground = true
		} else if e.vel_y < 0 {
			tile_y := int(hb.y) / TILE_SIZE
			e.pos.y = f32((tile_y + 1) * TILE_SIZE) + hb.height
		}
		e.vel_y = 0
	}
}

@(private = "file")
get_ghoul_fx_rect :: proc(e: ^Enemy) -> raylib.Rectangle {
	fx_size := f32(GHOUL_FX_FRAME_SIZE)
	fx_x: f32
	if e.facing_left {
		fx_x = e.pos.x - fx_size
	} else {
		fx_x = e.pos.x
	}
	return {fx_x, e.pos.y - fx_size, fx_size, fx_size}
}

@(private = "file")
draw_enemy :: proc(e: ^Enemy) {
	if e.state == .Inactive {
		return
	}

	tex: raylib.Texture2D
	frames: int
	switch e.type {
	case .Cherub:
		switch e.state {
		case .Patrol, .Chase:
			tex = cherub_move_tex
			frames = cherub_move_frames
		case .Attack:
			tex = cherub_attack_tex
			frames = cherub_attack_frames
		case .Hit, .Dead:
			tex = cherub_idle_tex
			frames = cherub_idle_frames
		case .Inactive:
			return
		}
	case .Ghoul:
		switch e.state {
		case .Patrol, .Chase, .Hit, .Dead:
			tex = ghoul_move_tex
			frames = ghoul_move_frames
		case .Attack:
			tex = ghoul_attack_tex
			frames = ghoul_attack_frames
		case .Inactive:
			return
		}
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

	// Draw ghoul attack FX
	if e.type == .Ghoul && e.state == .Attack && e.attack_fx_active {
		fx_frame := int(e.attack_fx_frame)
		if fx_frame >= ghoul_attack_fx_frames {
			fx_frame = ghoul_attack_fx_frames - 1
		}
		fx_size := f32(GHOUL_FX_FRAME_SIZE)
		fx_src := raylib.Rectangle {
			f32(fx_frame * GHOUL_FX_FRAME_SIZE), 0,
			e.facing_left ? -fx_size : fx_size,
			fx_size,
		}
		fx_dst := get_ghoul_fx_rect(e)
		raylib.DrawTexturePro(ghoul_attack_fx_tex, fx_src, fx_dst, {0, 0}, 0, raylib.WHITE)
	}
}

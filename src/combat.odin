package game

import "vendor:raylib"
import "core:math"

Target_Mode :: enum {
	None,
	Auto,
	Manual,
}

Throw_Phase :: enum {
	None,
	Windup,
	Flying,
	Hit,
	Returning,
}

Combat_State :: struct {
	target_mode:    Target_Mode,
	target_index:   int,
	throw_phase:    Throw_Phase,
	projectile_pos: raylib.Vector2,
	projectile_dir: raylib.Vector2,
	throw_timer:    f32,
	spin_frame:     f32,
	spin_timer:     f32,
	cycle_cooldown: f32,
}

@(private = "file")
projectile_tex: raylib.Texture2D
@(private = "file")
projectile_frames: int

init_combat :: proc(c: ^Combat_State) {
	projectile_tex = raylib.LoadTexture("assets/sprites/player_spear_throw.png")
	projectile_frames = int(projectile_tex.width) / SPEAR_SPRITE_SIZE
	c.target_index = -1
	c.target_mode = .None
	c.throw_phase = .None
}

unload_combat :: proc() {
	raylib.UnloadTexture(projectile_tex)
}

update_combat :: proc(
	c: ^Combat_State,
	p: ^Player,
	s: ^Spear,
	enemies: ^[MAX_ENEMIES]Enemy,
	enemy_count: int,
	dt: f32,
) {
	// --- Targeting ---
	if input_target_hold() {
		if c.target_mode != .Manual {
			c.target_mode = .Manual
			if c.target_index < 0 {
				c.target_index = find_nearest_target(p.pos, enemies, enemy_count)
			}
		}
		if input_cycle_target() && c.cycle_cooldown <= 0 && c.throw_phase == .None {
			cycle_target_in_range(c, p.pos, enemies, enemy_count)
			c.cycle_cooldown = 0.2
		}
	} else if c.target_mode == .Manual && c.throw_phase == .None {
		c.target_mode = .None
		c.target_index = -1
	}

	if c.cycle_cooldown > 0 {
		c.cycle_cooldown -= dt
	}

	// --- Attack ---
	if input_attack() && s.state == .Idle && c.throw_phase == .None {
		target := -1
		if c.target_mode == .Manual && c.target_index >= 0 && c.target_index < enemy_count {
			e := &enemies[c.target_index]
			if e.state == .Patrol || e.state == .Hit {
				target = c.target_index
			}
		}
		if target < 0 {
			target = find_nearest_target(p.pos, enemies, enemy_count)
			if target >= 0 {
				c.target_mode = .Auto
			}
		}
		if target >= 0 {
			c.target_index = target
			c.throw_phase = .Windup
			c.throw_timer = PLAYER_THROW_HOLD_TIME
			p.is_throwing = true
			s.state = .Throwing
			enemy_center := get_enemy_center(&enemies[target])
			p.facing_left = enemy_center.x < p.pos.x
		}
	}

	// --- Throw state machine ---
	#partial switch c.throw_phase {
	case .Windup:
		c.throw_timer -= dt
		if c.throw_timer <= 0 {
			p.is_throwing = false
			c.projectile_pos = {p.pos.x, p.pos.y - f32(PLAYER_HITBOX_H) / 2}
			enemy_center := get_enemy_center(&enemies[c.target_index])
			dx := enemy_center.x - c.projectile_pos.x
			dy := enemy_center.y - c.projectile_pos.y
			length := math.sqrt(dx * dx + dy * dy)
			if length > 0 {
				c.projectile_dir = {dx / length, dy / length}
			}
			c.throw_phase = .Flying
			c.spin_frame = 0
			c.spin_timer = 0
		}
	case .Flying:
		c.projectile_pos.x += c.projectile_dir.x * SPEAR_PROJECTILE_SPEED * dt
		c.projectile_pos.y += c.projectile_dir.y * SPEAR_PROJECTILE_SPEED * dt
		advance_spin(c, dt)

		hit := false
		if c.target_index >= 0 && c.target_index < enemy_count {
			e := &enemies[c.target_index]
			if e.state == .Patrol || e.state == .Hit {
				center := get_enemy_center(e)
				dx := center.x - c.projectile_pos.x
				dy := center.y - c.projectile_pos.y
				if dx * dx + dy * dy <= SPEAR_HIT_RADIUS * SPEAR_HIT_RADIUS {
					enemy_take_damage(e, SPEAR_THROW_DAMAGE)
					c.throw_phase = .Hit
					c.throw_timer = 0.05
					hit = true
				}
			} else {
				c.throw_phase = .Returning
				hit = true
			}
		} else {
			c.throw_phase = .Returning
			hit = true
		}

		if !hit {
			pdx := c.projectile_pos.x - p.pos.x
			pdy := c.projectile_pos.y - p.pos.y
			max_dist: f32 = COMBAT_RANGE * 1.5
			if pdx * pdx + pdy * pdy > max_dist * max_dist {
				c.throw_phase = .Returning
			}
		}
	case .Hit:
		c.throw_timer -= dt
		if c.throw_timer <= 0 {
			c.throw_phase = .Returning
		}
	case .Returning:
		player_center := raylib.Vector2{p.pos.x, p.pos.y - f32(PLAYER_HITBOX_H) / 2}
		dx := player_center.x - c.projectile_pos.x
		dy := player_center.y - c.projectile_pos.y
		dist_sq := dx * dx + dy * dy

		if dist_sq <= 16.0 {
			c.throw_phase = .None
			s.state = .Idle
			c.spin_frame = 0
			c.spin_timer = 0
			if c.target_mode == .Auto {
				c.target_mode = .None
				c.target_index = -1
			}
		} else {
			length := math.sqrt(dist_sq)
			c.projectile_pos.x += (dx / length) * SPEAR_RETURN_SPEED * dt
			c.projectile_pos.y += (dy / length) * SPEAR_RETURN_SPEED * dt
			advance_spin(c, dt)
		}
	}
}

draw_combat :: proc(c: ^Combat_State, enemies: ^[MAX_ENEMIES]Enemy, enemy_count: int) {
	// Targeting reticle
	if c.target_mode != .None && c.target_index >= 0 && c.target_index < enemy_count {
		e := &enemies[c.target_index]
		if e.state == .Patrol || e.state == .Hit {
			center := get_enemy_center(e)
			pulse := 1.0 + 0.15 * math.sin(f32(raylib.GetTime()) * 6.0)
			size := 10.0 * pulse
			color := raylib.Color{0xff, 0xcc, 0x00, 0xcc}
			raylib.DrawLineV({center.x, center.y - size}, {center.x + size, center.y}, color)
			raylib.DrawLineV({center.x + size, center.y}, {center.x, center.y + size}, color)
			raylib.DrawLineV({center.x, center.y + size}, {center.x - size, center.y}, color)
			raylib.DrawLineV({center.x - size, center.y}, {center.x, center.y - size}, color)
		}
	}

	// Projectile
	if c.throw_phase == .Flying || c.throw_phase == .Hit || c.throw_phase == .Returning {
		frame := int(c.spin_frame)
		if frame >= projectile_frames {
			frame = projectile_frames - 1
		}

		src := raylib.Rectangle{
			f32(frame * SPEAR_SPRITE_SIZE), 0,
			c.projectile_dir.x < 0 ? -f32(SPEAR_SPRITE_SIZE) : f32(SPEAR_SPRITE_SIZE),
			f32(SPEAR_SPRITE_SIZE),
		}

		half := f32(SPEAR_SPRITE_SIZE) / 2
		dst := raylib.Rectangle{
			c.projectile_pos.x - half,
			c.projectile_pos.y - half,
			f32(SPEAR_SPRITE_SIZE),
			f32(SPEAR_SPRITE_SIZE),
		}

		raylib.DrawTexturePro(projectile_tex, src, dst, {0, 0}, 0, raylib.WHITE)
	}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

@(private = "file")
find_nearest_target :: proc(player_pos: raylib.Vector2, enemies: ^[MAX_ENEMIES]Enemy, count: int) -> int {
	best_idx := -1
	best_dist_sq: f32 = COMBAT_RANGE * COMBAT_RANGE + 1
	range_sq: f32 = COMBAT_RANGE * COMBAT_RANGE

	for i in 0 ..< count {
		e := &enemies[i]
		if e.state == .Inactive || e.state == .Dead {
			continue
		}
		center := get_enemy_center(e)
		dx := center.x - player_pos.x
		dy := center.y - player_pos.y
		dist_sq := dx * dx + dy * dy
		if dist_sq <= range_sq && dist_sq < best_dist_sq {
			best_dist_sq = dist_sq
			best_idx = i
		}
	}
	return best_idx
}

@(private = "file")
cycle_target_in_range :: proc(
	c: ^Combat_State,
	player_pos: raylib.Vector2,
	enemies: ^[MAX_ENEMIES]Enemy,
	count: int,
) {
	valid: [MAX_ENEMIES]int
	valid_count := 0
	range_sq: f32 = COMBAT_RANGE * COMBAT_RANGE

	for i in 0 ..< count {
		e := &enemies[i]
		if e.state == .Inactive || e.state == .Dead {
			continue
		}
		center := get_enemy_center(e)
		dx := center.x - player_pos.x
		dy := center.y - player_pos.y
		if dx * dx + dy * dy <= range_sq {
			valid[valid_count] = i
			valid_count += 1
		}
	}

	if valid_count == 0 {
		c.target_index = -1
		return
	}

	current_pos := -1
	for i in 0 ..< valid_count {
		if valid[i] == c.target_index {
			current_pos = i
			break
		}
	}

	c.target_index = valid[(current_pos + 1) % valid_count]
}

@(private = "file")
advance_spin :: proc(c: ^Combat_State, dt: f32) {
	c.spin_timer += dt
	if c.spin_timer >= ANIM_FRAME_TIME {
		c.spin_timer -= ANIM_FRAME_TIME
		c.spin_frame += 1
		if int(c.spin_frame) >= projectile_frames {
			c.spin_frame = 0
		}
	}
}

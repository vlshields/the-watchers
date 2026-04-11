package game

import "vendor:raylib"
import dm "../dotmap"
import "core:math"

Target_Mode :: enum {
	None,
	Auto,
	Manual,
}

Target_Kind :: enum {
	None,
	Enemy,
	Sign,
}

Target_Ref :: struct {
	kind:  Target_Kind,
	index: int,
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
	target_kind:    Target_Kind,
	target_index:   int,
	throw_phase:    Throw_Phase,
	projectile_pos: raylib.Vector2,
	projectile_dir: raylib.Vector2,
	throw_timer:    f32,
	spin_frame:     f32,
	spin_timer:     f32,
	cycle_cooldown: f32,
	return_damaged: [MAX_ENEMIES]bool,
}

@(private = "file")
projectile_tex: raylib.Texture2D
@(private = "file")
projectile_frames: int

init_combat :: proc(c: ^Combat_State) {
	projectile_tex = raylib.LoadTexture("assets/sprites/player_spear_throw.png")
	projectile_frames = int(projectile_tex.width) / SPEAR_SPRITE_SIZE
	c.target_index = -1
	c.target_kind = .None
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
	map_data: ^dm.Dot_Map,
	enemies: ^[MAX_ENEMIES]Enemy,
	enemy_count: int,
	signs: ^[MAX_DECORATIVE_SIGNS]Decorative_Sign,
	sign_count: int,
	dt: f32,
) {
	// --- Targeting ---
	if input_target_hold() {
		if c.target_mode != .Manual {
			c.target_mode = .Manual
			if c.target_kind == .None || c.target_index < 0 {
				target := find_nearest_target(p.pos, enemies, enemy_count, signs, sign_count)
				set_combat_target(c, target)
			}
		}
		if input_cycle_target() && c.cycle_cooldown <= 0 && c.throw_phase == .None {
			cycle_target_in_range(c, p.pos, enemies, enemy_count, signs, sign_count)
			c.cycle_cooldown = 0.2
		}
	} else if c.target_mode == .Manual && c.throw_phase == .None {
		c.target_mode = .None
		clear_combat_target(c)
	}

	if c.cycle_cooldown > 0 {
		c.cycle_cooldown -= dt
	}

	if input_spear_teleport() && spear_can_teleport(c) {
		strike_target := teleport_strike_target(c, enemies, enemy_count)
		knockback_dir: f32 = 0
		if strike_target >= 0 {
			knockback_dir = teleport_strike_knockback_dir(p, &enemies[strike_target], c)
		}

		if teleport_player_to_spear(p, map_data, c.projectile_pos) {
			if strike_target >= 0 {
				enemy_take_teleport_strike(&enemies[strike_target], knockback_dir)
			}
			if c.target_kind == .Sign && c.target_index >= 0 && c.target_index < sign_count {
				signs[c.target_index].active = false
			}

			c.throw_phase = .None
			s.state = .Idle
			c.spin_frame = 0
			c.spin_timer = 0
			p.is_throwing = false
			if c.target_kind == .Sign {
				clear_combat_target(c)
				c.target_mode = .None
			}
			if c.target_mode == .Auto {
				c.target_mode = .None
				clear_combat_target(c)
			}
		}
	}

	// --- Attack ---
	if input_attack() && s.state == .Idle && c.throw_phase == .None {
		target := Target_Ref{kind = .None, index = -1}
		if c.target_mode == .Manual {
			manual_target := Target_Ref{kind = c.target_kind, index = c.target_index}
			if combat_target_valid(manual_target, enemies, enemy_count, signs, sign_count) {
				target = manual_target
			}
		}
		if target.kind == .None {
			target = find_nearest_target(p.pos, enemies, enemy_count, signs, sign_count)
			if target.kind != .None {
				c.target_mode = .Auto
			}
		}
		if target.kind != .None {
			set_combat_target(c, target)
			c.throw_phase = .Windup
			c.throw_timer = ANIM_PLAYER_THROWS_SPEAR_TIME
			p.is_throwing = true
			p.current_frame = 0
			p.anim_timer = 0
			s.state = .Throwing
			target_center := get_combat_target_center(target, enemies, signs)
			p.facing_left = target_center.x < p.pos.x
		}
	}

	// --- Throw state machine ---
	#partial switch c.throw_phase {
	case .Windup:
		c.throw_timer -= dt
		if c.throw_timer <= 0 {
			p.is_throwing = false
			c.projectile_pos = {p.pos.x, p.pos.y - f32(PLAYER_HITBOX_H) / 2}
			target := Target_Ref{kind = c.target_kind, index = c.target_index}
			target_center := get_combat_target_center(target, enemies, signs)
			dx := target_center.x - c.projectile_pos.x
			dy := target_center.y - c.projectile_pos.y
			length := math.sqrt(dx * dx + dy * dy)
			if length > 0 {
				c.projectile_dir = {dx / length, dy / length}
			}
			c.throw_phase = .Flying
			c.spin_frame = 0
			c.spin_timer = 0
		}
	case .Flying:
		prev_pos := c.projectile_pos
		c.projectile_pos.x += c.projectile_dir.x * SPEAR_PROJECTILE_SPEED * dt
		c.projectile_pos.y += c.projectile_dir.y * SPEAR_PROJECTILE_SPEED * dt
		advance_spin(c, dt)

		hit := false
		target := Target_Ref{kind = c.target_kind, index = c.target_index}
		if combat_target_valid(target, enemies, enemy_count, signs, sign_count) {
			if spear_segment_hits_target(prev_pos, c.projectile_pos, target, enemies, signs) {
				if target.kind == .Enemy {
					e := &enemies[target.index]
					enemy_take_damage(e, SPEAR_THROW_DAMAGE)
				}
				c.throw_phase = .Hit
				c.throw_timer = SPEAR_HIT_PAUSE_TIME
				hit = true
			}
		} else {
			begin_spear_return(c)
			hit = true
		}

		if !hit {
			pdx := c.projectile_pos.x - p.pos.x
			pdy := c.projectile_pos.y - p.pos.y
			max_dist: f32 = COMBAT_RANGE * 1.5
			if pdx * pdx + pdy * pdy > max_dist * max_dist {
				begin_spear_return(c)
			}
		}
	case .Hit:
		c.throw_timer -= dt
		if c.throw_timer <= 0 {
			begin_spear_return(c)
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
				clear_combat_target(c)
			}
		} else {
			length := math.sqrt(dist_sq)
			prev_pos := c.projectile_pos
			c.projectile_pos.x += (dx / length) * SPEAR_RETURN_SPEED * dt
			c.projectile_pos.y += (dy / length) * SPEAR_RETURN_SPEED * dt
			damage_enemies_on_spear_return(c, enemies, enemy_count, prev_pos, c.projectile_pos)
			advance_spin(c, dt)
		}
	}
}

draw_combat :: proc(
	c: ^Combat_State,
	enemies: ^[MAX_ENEMIES]Enemy,
	enemy_count: int,
	signs: ^[MAX_DECORATIVE_SIGNS]Decorative_Sign,
	sign_count: int,
) {
	// Targeting reticle
	target := Target_Ref{kind = c.target_kind, index = c.target_index}
	if c.target_mode != .None && combat_target_valid(target, enemies, enemy_count, signs, sign_count) {
		center := get_combat_target_center(target, enemies, signs)
		pulse := 1.0 + 0.15 * math.sin(f32(raylib.GetTime()) * 6.0)
		size := 10.0 * pulse
		color := raylib.Color{0xff, 0xcc, 0x00, 0xcc}
		raylib.DrawLineV({center.x, center.y - size}, {center.x + size, center.y}, color)
		raylib.DrawLineV({center.x + size, center.y}, {center.x, center.y + size}, color)
		raylib.DrawLineV({center.x, center.y + size}, {center.x - size, center.y}, color)
		raylib.DrawLineV({center.x - size, center.y}, {center.x, center.y - size}, color)
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
find_nearest_target :: proc(
	player_pos: raylib.Vector2,
	enemies: ^[MAX_ENEMIES]Enemy,
	enemy_count: int,
	signs: ^[MAX_DECORATIVE_SIGNS]Decorative_Sign,
	sign_count: int,
) -> Target_Ref {
	best := Target_Ref{kind = .None, index = -1}
	best_dist_sq: f32 = COMBAT_RANGE * COMBAT_RANGE + 1
	range_sq: f32 = COMBAT_RANGE * COMBAT_RANGE

	for i in 0 ..< enemy_count {
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
			best = {kind = .Enemy, index = i}
		}
	}

	for i in 0 ..< sign_count {
		sign := &signs[i]
		if !sign.active {
			continue
		}
		center := get_decorative_sign_center(sign)
		dx := center.x - player_pos.x
		dy := center.y - player_pos.y
		dist_sq := dx * dx + dy * dy
		if dist_sq <= range_sq && dist_sq < best_dist_sq {
			best_dist_sq = dist_sq
			best = {kind = .Sign, index = i}
		}
	}

	return best
}

@(private = "file")
cycle_target_in_range :: proc(
	c: ^Combat_State,
	player_pos: raylib.Vector2,
	enemies: ^[MAX_ENEMIES]Enemy,
	enemy_count: int,
	signs: ^[MAX_DECORATIVE_SIGNS]Decorative_Sign,
	sign_count: int,
) {
	valid: [MAX_COMBAT_TARGETS]Target_Ref
	valid_count := 0
	range_sq: f32 = COMBAT_RANGE * COMBAT_RANGE

	for i in 0 ..< enemy_count {
		e := &enemies[i]
		if e.state == .Inactive || e.state == .Dead {
			continue
		}
		center := get_enemy_center(e)
		dx := center.x - player_pos.x
		dy := center.y - player_pos.y
		if dx * dx + dy * dy <= range_sq {
			valid[valid_count] = {kind = .Enemy, index = i}
			valid_count += 1
		}
	}

	for i in 0 ..< sign_count {
		sign := &signs[i]
		if !sign.active {
			continue
		}
		center := get_decorative_sign_center(sign)
		dx := center.x - player_pos.x
		dy := center.y - player_pos.y
		if dx * dx + dy * dy <= range_sq {
			valid[valid_count] = {kind = .Sign, index = i}
			valid_count += 1
		}
	}

	if valid_count == 0 {
		clear_combat_target(c)
		return
	}

	current_pos := -1
	for i in 0 ..< valid_count {
		if valid[i].kind == c.target_kind && valid[i].index == c.target_index {
			current_pos = i
			break
		}
	}

	set_combat_target(c, valid[(current_pos + 1) % valid_count])
}

@(private = "file")
set_combat_target :: proc(c: ^Combat_State, target: Target_Ref) {
	c.target_kind = target.kind
	c.target_index = target.index
}

@(private = "file")
clear_combat_target :: proc(c: ^Combat_State) {
	c.target_kind = .None
	c.target_index = -1
}

@(private = "file")
combat_target_valid :: proc(
	target: Target_Ref,
	enemies: ^[MAX_ENEMIES]Enemy,
	enemy_count: int,
	signs: ^[MAX_DECORATIVE_SIGNS]Decorative_Sign,
	sign_count: int,
) -> bool {
	switch target.kind {
	case .Enemy:
		if target.index < 0 || target.index >= enemy_count {
			return false
		}
		e := &enemies[target.index]
		return e.state != .Inactive && e.state != .Dead
	case .Sign:
		if target.index < 0 || target.index >= sign_count {
			return false
		}
		return signs[target.index].active
	case .None:
		return false
	}
	return false
}

@(private = "file")
get_combat_target_center :: proc(
	target: Target_Ref,
	enemies: ^[MAX_ENEMIES]Enemy,
	signs: ^[MAX_DECORATIVE_SIGNS]Decorative_Sign,
) -> raylib.Vector2 {
	switch target.kind {
	case .Enemy:
		return get_enemy_center(&enemies[target.index])
	case .Sign:
		return get_decorative_sign_center(&signs[target.index])
	case .None:
		return {}
	}
	return {}
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

@(private = "file")
teleport_strike_target :: proc(
	c: ^Combat_State,
	enemies: ^[MAX_ENEMIES]Enemy,
	enemy_count: int,
) -> int {
	if c.throw_phase != .Hit || c.target_kind != .Enemy ||
		c.target_index < 0 || c.target_index >= enemy_count {
		return -1
	}

	e := &enemies[c.target_index]
	if e.state == .Inactive || e.state == .Dead {
		return -1
	}
	return c.target_index
}

@(private = "file")
teleport_strike_knockback_dir :: proc(p: ^Player, e: ^Enemy, c: ^Combat_State) -> f32 {
	center := get_enemy_center(e)
	dir := center.x - p.pos.x
	if abs(dir) < 0.01 {
		dir = c.projectile_dir.x
	}
	if dir < 0 {
		return -1
	}
	return 1
}

@(private = "file")
begin_spear_return :: proc(c: ^Combat_State) {
	c.throw_phase = .Returning
	for &damaged in c.return_damaged {
		damaged = false
	}
}

@(private = "file")
damage_enemies_on_spear_return :: proc(
	c: ^Combat_State,
	enemies: ^[MAX_ENEMIES]Enemy,
	enemy_count: int,
	from, to: raylib.Vector2,
) {
	for i in 0 ..< enemy_count {
		if c.return_damaged[i] {
			continue
		}

		e := &enemies[i]
		if e.state == .Inactive || e.state == .Dead {
			continue
		}

		if spear_segment_hits_enemy(from, to, e) {
			enemy_take_damage(e, SPEAR_THROW_DAMAGE)
			c.return_damaged[i] = true
		}
	}
}

@(private = "file")
spear_segment_hits_target :: proc(
	from, to: raylib.Vector2,
	target: Target_Ref,
	enemies: ^[MAX_ENEMIES]Enemy,
	signs: ^[MAX_DECORATIVE_SIGNS]Decorative_Sign,
) -> bool {
	switch target.kind {
	case .Enemy:
		return spear_segment_hits_enemy(from, to, &enemies[target.index])
	case .Sign:
		center := get_decorative_sign_center(&signs[target.index])
		rect := raylib.Rectangle {
			center.x - f32(SPRITE_DST_SIZE) / 2 - SPEAR_HIT_RADIUS,
			center.y - f32(SPRITE_DST_SIZE) / 2 - SPEAR_HIT_RADIUS,
			f32(SPRITE_DST_SIZE) + SPEAR_HIT_RADIUS * 2,
			f32(SPRITE_DST_SIZE) + SPEAR_HIT_RADIUS * 2,
		}
		return point_in_rect(from, rect) ||
			point_in_rect(to, rect) ||
			segment_intersects_rect(from, to, rect)
	case .None:
		return false
	}
	return false
}

@(private = "file")
spear_segment_hits_enemy :: proc(from, to: raylib.Vector2, enemy: ^Enemy) -> bool {
	hb := get_enemy_hitbox(enemy)
	expanded := raylib.Rectangle {
		hb.x - SPEAR_HIT_RADIUS,
		hb.y - SPEAR_HIT_RADIUS,
		hb.width + SPEAR_HIT_RADIUS * 2,
		hb.height + SPEAR_HIT_RADIUS * 2,
	}

	return point_in_rect(from, expanded) ||
		point_in_rect(to, expanded) ||
		segment_intersects_rect(from, to, expanded)
}

@(private = "file")
point_in_rect :: proc(p: raylib.Vector2, rect: raylib.Rectangle) -> bool {
	return p.x >= rect.x && p.x <= rect.x + rect.width &&
		p.y >= rect.y && p.y <= rect.y + rect.height
}

@(private = "file")
segment_intersects_rect :: proc(a, b: raylib.Vector2, rect: raylib.Rectangle) -> bool {
	t_min: f32 = 0
	t_max: f32 = 1
	dx := b.x - a.x
	dy := b.y - a.y

	if !clip_segment_axis(a.x, dx, rect.x, rect.x + rect.width, &t_min, &t_max) {
		return false
	}
	if !clip_segment_axis(a.y, dy, rect.y, rect.y + rect.height, &t_min, &t_max) {
		return false
	}
	return true
}

@(private = "file")
clip_segment_axis :: proc(
	start, delta, min_bound, max_bound: f32,
	t_min, t_max: ^f32,
) -> bool {
	if delta == 0 {
		return start >= min_bound && start <= max_bound
	}

	inv_delta := 1 / delta
	t1 := (min_bound - start) * inv_delta
	t2 := (max_bound - start) * inv_delta
	if t1 > t2 {
		t1, t2 = t2, t1
	}
	if t1 > t_min^ {
		t_min^ = t1
	}
	if t2 < t_max^ {
		t_max^ = t2
	}
	return t_min^ <= t_max^
}

@(private = "file")
spear_can_teleport :: proc(c: ^Combat_State) -> bool {
	return c.throw_phase == .Flying ||
		c.throw_phase == .Hit ||
		c.throw_phase == .Returning
}

@(private = "file")
teleport_player_to_spear :: proc(p: ^Player, map_data: ^dm.Dot_Map, spear_pos: raylib.Vector2) -> bool {
	dest: raylib.Vector2
	if !find_spear_teleport_destination(map_data, spear_pos, &dest) {
		return false
	}

	p.pos = dest
	p.vel = {}
	p.on_ground = player_on_ground_at(map_data, dest)
	p.jumps_left = p.on_ground ? MAX_JUMPS : 1
	start_player_teleport_animation(p)
	return true
}

@(private = "file")
find_spear_teleport_destination :: proc(
	map_data: ^dm.Dot_Map,
	spear_pos: raylib.Vector2,
	dest: ^raylib.Vector2,
) -> bool {
	base := raylib.Vector2 {
		spear_pos.x,
		spear_pos.y + f32(PLAYER_HITBOX_H) / 2,
	}

	if player_position_clear(map_data, base) {
		dest^ = base
		return true
	}

	best_pos: raylib.Vector2
	best_score: f32 = 1e9
	found := false

	for y_off := -TELEPORT_SEARCH_RADIUS; y_off <= TELEPORT_SEARCH_RADIUS; y_off += TELEPORT_SEARCH_STEP {
		for x_off := -TELEPORT_SEARCH_RADIUS; x_off <= TELEPORT_SEARCH_RADIUS; x_off += TELEPORT_SEARCH_STEP {
			candidate := raylib.Vector2 {
				base.x + f32(x_off),
				base.y + f32(y_off),
			}
			if !player_position_clear(map_data, candidate) {
				continue
			}

			score := f32(x_off * x_off + y_off * y_off)
			if y_off > 0 {
				score += TELEPORT_BELOW_PENALTY
			}
			if score < best_score {
				best_score = score
				best_pos = candidate
				found = true
			}
		}
	}

	if found {
		dest^ = best_pos
	}
	return found
}

@(private = "file")
player_position_clear :: proc(map_data: ^dm.Dot_Map, pos: raylib.Vector2) -> bool {
	rect := raylib.Rectangle {
		pos.x - f32(PLAYER_HITBOX_W) / 2,
		pos.y - f32(PLAYER_HITBOX_H),
		f32(PLAYER_HITBOX_W),
		f32(PLAYER_HITBOX_H),
	}
	return !check_rect_solid(map_data, rect)
}

@(private = "file")
player_on_ground_at :: proc(map_data: ^dm.Dot_Map, pos: raylib.Vector2) -> bool {
	rect := raylib.Rectangle {
		pos.x - f32(PLAYER_HITBOX_W) / 2,
		pos.y,
		f32(PLAYER_HITBOX_W),
		1,
	}
	return check_rect_solid(map_data, rect)
}

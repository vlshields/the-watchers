package game

import "vendor:raylib"
import dm "../dotmap"

// ---------------------------------------------------------------------------
// Psychic projectile — fired by cherubs toward the player
// ---------------------------------------------------------------------------

PSY_TRAIL_LEN :: 5

Psychic_Projectile :: struct {
	active:    bool,
	pos:       raylib.Vector2,
	vel:       raylib.Vector2,
	lifetime:  f32,
	trail:     [PSY_TRAIL_LEN]raylib.Vector2,
	trail_len: int,
}

PSY_COLOR :: raylib.Color{0xd5, 0xdc, 0x1d, 255}

spawn_psychic_projectile :: proc(
	projectiles: ^[MAX_PSYCHIC_PROJECTILES]Psychic_Projectile,
	count: ^int,
	origin: raylib.Vector2,
	vel: raylib.Vector2,
) {
	if count^ >= MAX_PSYCHIC_PROJECTILES {
		return
	}
	p := &projectiles[count^]
	p.active = true
	p.pos = origin
	p.vel = vel
	p.lifetime = PSYCHIC_LIFETIME
	p.trail_len = 0
	count^ += 1
}

update_psychic_projectiles :: proc(
	projectiles: ^[MAX_PSYCHIC_PROJECTILES]Psychic_Projectile,
	count: ^int,
	player: ^Player,
	map_data: ^dm.Dot_Map,
	dt: f32,
) {
	i := 0
	for i < count^ {
		p := &projectiles[i]
		if !p.active {
			// Compact: swap with last
			projectiles[i] = projectiles[count^ - 1]
			projectiles[count^ - 1].active = false
			count^ -= 1
			continue
		}

		// Shift trail history
		for t := PSY_TRAIL_LEN - 1; t > 0; t -= 1 {
			p.trail[t] = p.trail[t - 1]
		}
		p.trail[0] = p.pos
		if p.trail_len < PSY_TRAIL_LEN {
			p.trail_len += 1
		}

		prev_pos := p.pos
		if psychic_projectile_hits_player(prev_pos, p.pos, player) {
			player_take_damage(player, PSYCHIC_DAMAGE)
			p.active = false
			continue
		}

		// Gravity arc
		p.vel.y += PSYCHIC_ARC_GRAVITY * dt
		p.pos.x += p.vel.x * dt
		p.pos.y += p.vel.y * dt
		p.lifetime -= dt

		// Hit player
		if psychic_projectile_hits_player(prev_pos, p.pos, player) {
			player_take_damage(player, PSYCHIC_DAMAGE)
			p.active = false
			continue
		}

		// Expire
		if p.lifetime <= 0 {
			p.active = false
			continue
		}

		i += 1
	}
}

draw_psychic_projectiles :: proc(
	projectiles: ^[MAX_PSYCHIC_PROJECTILES]Psychic_Projectile,
	count: int,
) {
	for i in 0 ..< count {
		p := &projectiles[i]
		if !p.active {
			continue
		}

		// Trail: fading pixels behind the projectile
		for t in 0 ..< p.trail_len {
			alpha := u8(180 - 180 * t / PSY_TRAIL_LEN)
			c := raylib.Color{PSY_COLOR.r, PSY_COLOR.g, PSY_COLOR.b, alpha}
			raylib.DrawPixelV(p.trail[t], c)
		}

		// Core: small filled circle
		raylib.DrawCircleV(p.pos, 2, PSY_COLOR)
	}
}

@(private = "file")
psychic_projectile_hits_player :: proc(from, to: raylib.Vector2, player: ^Player) -> bool {
	hb := get_hitbox(player)
	radius: f32 = 2
	expanded := raylib.Rectangle {
		hb.x - radius,
		hb.y - radius,
		hb.width + radius * 2,
		hb.height + radius * 2,
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

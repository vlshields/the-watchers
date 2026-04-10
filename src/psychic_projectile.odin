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

		// Gravity arc
		p.vel.y += PSYCHIC_ARC_GRAVITY * dt
		p.pos.x += p.vel.x * dt
		p.pos.y += p.vel.y * dt
		p.lifetime -= dt

		// Hit player
		phb := get_hitbox(player)
		if p.pos.x >= phb.x && p.pos.x <= phb.x + phb.width &&
			p.pos.y >= phb.y && p.pos.y <= phb.y + phb.height {
			player_take_damage(player, PSYCHIC_DAMAGE)
			p.active = false
			continue
		}

		// Hit solid tile
		if check_rect_solid(map_data, {p.pos.x - 2, p.pos.y - 2, 4, 4}) {
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

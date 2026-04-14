package game

import "vendor:raylib"
import "core:math/rand"

Dust_Particle :: struct {
	active:       bool,
	pos:          raylib.Vector2,
	vel:          raylib.Vector2,
	lifetime:     f32,
	max_lifetime: f32,
	radius:       f32,
	color:        raylib.Color,
}

@(private = "file")
dust_particles: [MAX_DUST_PARTICLES]Dust_Particle

@(private = "file")
dust_next: int

@(private = "file")
DUST_BASE_COLOR :: raylib.Color{210, 198, 170, 255}

init_dust_particles :: proc() {
	for i in 0 ..< MAX_DUST_PARTICLES {
		dust_particles[i].active = false
	}
	dust_next = 0
}

update_dust_particles :: proc(dt: f32) {
	for i in 0 ..< MAX_DUST_PARTICLES {
		p := &dust_particles[i]
		if !p.active {
			continue
		}
		p.lifetime -= dt
		if p.lifetime <= 0 {
			p.active = false
			continue
		}
		p.vel.y += DUST_GRAVITY * dt
		p.vel.x *= 0.92
		p.pos.x += p.vel.x * dt
		p.pos.y += p.vel.y * dt
	}
}

draw_dust_particles :: proc() {
	for i in 0 ..< MAX_DUST_PARTICLES {
		p := &dust_particles[i]
		if !p.active {
			continue
		}
		t := p.lifetime / p.max_lifetime
		if t < 0 {
			t = 0
		}
		c := p.color
		c.a = u8(f32(p.color.a) * t)
		r := p.radius * (0.4 + 0.6 * t)
		raylib.DrawCircleV(p.pos, r, c)
	}
}

@(private = "file")
emit_dust :: proc(pos: raylib.Vector2, vel: raylib.Vector2, radius: f32, life: f32) {
	start := dust_next
	for offset in 0 ..< MAX_DUST_PARTICLES {
		idx := (start + offset) % MAX_DUST_PARTICLES
		if !dust_particles[idx].active {
			dust_particles[idx] = Dust_Particle{
				active       = true,
				pos          = pos,
				vel          = vel,
				lifetime     = life,
				max_lifetime = life,
				radius       = radius,
				color        = DUST_BASE_COLOR,
			}
			dust_next = (idx + 1) % MAX_DUST_PARTICLES
			return
		}
	}
	dust_particles[start] = Dust_Particle{
		active       = true,
		pos          = pos,
		vel          = vel,
		lifetime     = life,
		max_lifetime = life,
		radius       = radius,
		color        = DUST_BASE_COLOR,
	}
	dust_next = (start + 1) % MAX_DUST_PARTICLES
}

spawn_dust_step :: proc(pos: raylib.Vector2, facing_left: bool) {
	dir: f32 = facing_left ? 1 : -1
	count := 2
	for i in 0 ..< count {
		_ = i
		vx := dir * rand.float32_range(8, 22)
		vy := rand.float32_range(-22, -8)
		ox := rand.float32_range(-2, 2)
		emit_dust(
			{pos.x + ox, pos.y - 1},
			{vx, vy},
			rand.float32_range(1.2, 2.0),
			DUST_LIFETIME * 0.7,
		)
	}
}

spawn_dust_jump :: proc(pos: raylib.Vector2) {
	count := 6
	for i in 0 ..< count {
		_ = i
		vx := rand.float32_range(-40, 40)
		vy := rand.float32_range(-40, -10)
		ox := rand.float32_range(-4, 4)
		emit_dust(
			{pos.x + ox, pos.y - 1},
			{vx, vy},
			rand.float32_range(1.4, 2.4),
			DUST_LIFETIME,
		)
	}
}

spawn_dust_land :: proc(pos: raylib.Vector2, impact: f32) {
	count := 8
	speed_scale := clamp(impact / MAX_FALL_SPEED, 0.4, 1.2)
	for i in 0 ..< count {
		_ = i
		vx := rand.float32_range(-60, 60) * speed_scale
		vy := rand.float32_range(-50, -15) * speed_scale
		ox := rand.float32_range(-5, 5)
		emit_dust(
			{pos.x + ox, pos.y - 1},
			{vx, vy},
			rand.float32_range(1.6, 2.8),
			DUST_LIFETIME,
		)
	}
}

package game

import "vendor:raylib"

Spear_State :: enum {
	Inactive,
	Spawning,
	Idle,
	Despawning,
	Throwing,
	Returning,
}

Spear :: struct {
	state:          Spear_State,
	facing_left:    bool,
	moving:         bool,
	spawn_tex:      raylib.Texture2D,
	idle_tex:       raylib.Texture2D,
	move_tex:       raylib.Texture2D,
	despawn_tex:    raylib.Texture2D,
	spawn_frames:   int,
	idle_frames:    int,
	move_frames:    int,
	despawn_frames: int,
	current_frame:  f32,
	anim_timer:     f32,
}

init_spear :: proc(s: ^Spear) {
	s.state = .Inactive
	s.facing_left = false
	s.moving = false
	s.current_frame = 0
	s.anim_timer = 0

	s.spawn_tex = raylib.LoadTexture("assets/sprites/player_spear_spawn.png")
	s.idle_tex = raylib.LoadTexture("assets/sprites/player_spear_idle.png")
	s.move_tex = raylib.LoadTexture("assets/sprites/player_spear_move.png")
	s.despawn_tex = raylib.LoadTexture("assets/sprites/player_spear_despawn.png")
	s.spawn_frames = int(s.spawn_tex.width) / SPEAR_SPRITE_SIZE
	s.idle_frames = int(s.idle_tex.width) / SPEAR_SPRITE_SIZE
	s.move_frames = int(s.move_tex.width) / SPEAR_SPRITE_SIZE
	s.despawn_frames = int(s.despawn_tex.width) / SPEAR_SPRITE_SIZE
}

unload_spear :: proc(s: ^Spear) {
	raylib.UnloadTexture(s.spawn_tex)
	raylib.UnloadTexture(s.idle_tex)
	raylib.UnloadTexture(s.move_tex)
	raylib.UnloadTexture(s.despawn_tex)
}

update_spear :: proc(s: ^Spear, p: ^Player, dt: f32) {
	switch s.state {
	case .Inactive:
		if input_spear_toggle() {
			s.state = .Spawning
			s.facing_left = p.facing_left
			s.moving = p.moving
			s.current_frame = 0
			s.anim_timer = 0
		}

	case .Spawning:
		spear_advance_oneshot(s, s.spawn_frames, dt, raylib.EaseBackOut)
		if int(s.current_frame) >= s.spawn_frames {
			s.state = .Idle
			s.current_frame = 0
			s.anim_timer = 0
		}

	case .Idle:
		if input_spear_toggle() {
			s.state = .Despawning
			s.current_frame = 0
			s.anim_timer = 0
			return
		}

		spear_sync_facing(s, p)
		spear_animate_loop(s, dt)

	case .Despawning:
		spear_advance_oneshot(s, s.despawn_frames, dt, raylib.EaseCubicIn)
		if int(s.current_frame) >= s.despawn_frames {
			s.state = .Inactive
			s.current_frame = 0
			s.anim_timer = 0
		}
	case .Throwing, .Returning:
		return
	}
}

draw_spear :: proc(s: ^Spear, p: ^Player) {
	if s.state == .Inactive || s.state == .Throwing || s.state == .Returning {
		return
	}

	tex: raylib.Texture2D
	frames: int
	switch s.state {
	case .Spawning:
		tex = s.spawn_tex
		frames = s.spawn_frames
	case .Despawning:
		tex = s.despawn_tex
		frames = s.despawn_frames
	case .Idle:
		if s.moving {
			tex = s.move_tex
			frames = s.move_frames
		} else {
			tex = s.idle_tex
			frames = s.idle_frames
		}
	case .Inactive, .Throwing, .Returning:
		return
	}

	frame := int(s.current_frame)
	if frame >= frames {
		frame = frames - 1
	}

	src := raylib.Rectangle{
		f32(frame * SPEAR_SPRITE_SIZE), 0,
		s.facing_left ? -f32(SPEAR_SPRITE_SIZE) : f32(SPEAR_SPRITE_SIZE),
		f32(SPEAR_SPRITE_SIZE),
	}

	offset := f32(SPEAR_SPRITE_SIZE - SPRITE_DST_SIZE) / 2
	dst := raylib.Rectangle{
		p.pos.x - SPRITE_DST_SIZE / 2 - offset,
		p.pos.y - SPRITE_DST_SIZE - offset - 4,
		f32(SPEAR_SPRITE_SIZE),
		f32(SPEAR_SPRITE_SIZE),
	}

	raylib.DrawTexturePro(tex, src, dst, {0, 0}, 0, raylib.WHITE)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

@(private = "file")
spear_advance_oneshot :: proc(s: ^Spear, total_frames: int, dt: f32, ease: proc(f32, f32, f32, f32) -> f32) {
	total_dur: f32 = f32(total_frames) * ANIM_SPEAR_SPAWN_TIME
	s.anim_timer += dt
	if s.anim_timer >= total_dur {
		s.anim_timer = total_dur
		s.current_frame = f32(total_frames)
	} else {
		s.current_frame = ease(s.anim_timer, 0, f32(total_frames), total_dur)
	}
}

@(private = "file")
spear_sync_facing :: proc(s: ^Spear, p: ^Player) {
	was_moving := s.moving
	s.moving = p.moving
	s.facing_left = p.facing_left

	if s.moving != was_moving {
		s.current_frame = 0
		s.anim_timer = 0
	}
}

@(private = "file")
spear_animate_loop :: proc(s: ^Spear, dt: f32) {
	frames := s.moving ? s.move_frames : s.idle_frames
	frame_time: f32 = s.moving ? ANIM_FRAME_TIME : ANIM_SPEAR_IDLE_TIME
	if frames > 1 {
		s.anim_timer += dt
		if s.anim_timer >= frame_time {
			s.anim_timer -= frame_time
			s.current_frame += 1
			if int(s.current_frame) >= frames {
				s.current_frame = 0
			}
		}
	}
}

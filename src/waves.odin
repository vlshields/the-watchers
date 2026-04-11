package game

import "core:math/rand"
import "core:strings"
import "vendor:raylib"
import dm "../dotmap"

Wave_Encounter_State :: enum {
	Inactive,
	Ready,
	Running,
	Complete,
}

Wave_Encounter :: struct {
	state:            Wave_Encounter_State,
	trigger_row:      int,
	platform_x0:      int,
	platform_x1:      int,
	total_waves:      int,
	enemies_per_wave: int,
	current_wave:     int,
	enemy_types:      [MAX_WAVE_ENEMY_TYPES]Enemy_Type,
	enemy_type_count: int,
}

init_wave_encounter :: proc(w: ^Wave_Encounter, map_data: ^dm.Dot_Map) {
	w.state = .Inactive
	w.trigger_row = -1
	w.platform_x0 = -1
	w.platform_x1 = -1
	w.current_wave = 0
	w.total_waves = 0
	w.enemies_per_wave = 0
	w.enemy_type_count = 0

	for row, ry in map_data.grid {
		for cell, cx in row {
			if cell.symbol != 'T' {
				continue
			}

			td, has_meta := map_data.metadata['T']
			if !has_meta {
				continue
			}

			waves := dm.extract_kv(td.other, "waves")
			enemies_per_wave := dm.extract_kv(td.other, "enemies_per_wave")
			any := dm.extract_kv(td.other, "any")
			defer delete(waves)
			defer delete(enemies_per_wave)
			defer delete(any)

			w.total_waves = parse_positive_int(waves, 1)
			w.enemies_per_wave = parse_positive_int(enemies_per_wave, 1)
			parse_enemy_type_list(any, &w.enemy_types, &w.enemy_type_count)
			if w.enemy_type_count == 0 {
				w.enemy_types[0] = .Ghoul
				w.enemy_type_count = 1
			}

			w.trigger_row = ry
			w.platform_x0 = cx
			w.platform_x1 = cx
			for w.platform_x0 > 0 && is_platform_tile(map_data, w.platform_x0 - 1, ry) {
				w.platform_x0 -= 1
			}
			for w.platform_x1 + 1 < len(row) && is_platform_tile(map_data, w.platform_x1 + 1, ry) {
				w.platform_x1 += 1
			}
			w.state = .Ready
			return
		}
	}
}

update_wave_encounter :: proc(
	w: ^Wave_Encounter,
	player: ^Player,
	map_data: ^dm.Dot_Map,
	enemies: ^[MAX_ENEMIES]Enemy,
	enemy_count: ^int,
	camera: raylib.Camera2D,
) {
	switch w.state {
	case .Inactive, .Complete:
		return
	case .Ready:
		if player_on_wave_platform(w, player) {
			w.state = .Running
			spawn_next_wave(w, map_data, enemies, enemy_count, camera)
		}
	case .Running:
		if wave_enemies_alive(enemies, enemy_count^) {
			return
		}
		if w.current_wave >= w.total_waves {
			w.state = .Complete
			return
		}
		spawn_next_wave(w, map_data, enemies, enemy_count, camera)
	}
}

@(private = "file")
player_on_wave_platform :: proc(w: ^Wave_Encounter, player: ^Player) -> bool {
	if !player.on_ground || w.trigger_row < 0 {
		return false
	}

	tx := int(player.pos.x) / TILE_SIZE
	ty := int(player.pos.y + 1) / TILE_SIZE
	return ty == w.trigger_row && tx >= w.platform_x0 && tx <= w.platform_x1
}

@(private = "file")
spawn_next_wave :: proc(
	w: ^Wave_Encounter,
	map_data: ^dm.Dot_Map,
	enemies: ^[MAX_ENEMIES]Enemy,
	enemy_count: ^int,
	camera: raylib.Camera2D,
) {
	w.current_wave += 1
	for _ in 0 ..< w.enemies_per_wave {
		if enemy_count^ >= MAX_ENEMIES {
			return
		}

		enemy_type := w.enemy_types[rand.int_max(w.enemy_type_count)]
		pos := choose_wave_spawn_pos(w, camera)
		e := &enemies[enemy_count^]
		init_enemy_at(e, enemy_type, pos)
		e.aggroed = true
		e.wave_spawned = true
		e.state = .Chase
		enemy_count^ += 1
	}
}

@(private = "file")
choose_wave_spawn_pos :: proc(w: ^Wave_Encounter, camera: raylib.Camera2D) -> raylib.Vector2 {
	cam_half_w := f32(SCREEN_WIDTH) / (2 * camera.zoom)

	for _ in 0 ..< WAVE_SPAWN_ATTEMPTS {
		tx := rand.int_range(w.platform_x0, w.platform_x1 + 1)
		pos := wave_spawn_pos_for_tile(w, tx)
		if abs(pos.x - camera.target.x) > cam_half_w {
			return pos
		}
	}

	tx := rand.int_range(w.platform_x0, w.platform_x1 + 1)
	return wave_spawn_pos_for_tile(w, tx)
}

@(private = "file")
wave_spawn_pos_for_tile :: proc(w: ^Wave_Encounter, tx: int) -> raylib.Vector2 {
	return {
		f32(tx) * TILE_SIZE + TILE_SIZE / 2,
		f32(w.trigger_row) * TILE_SIZE,
	}
}

@(private = "file")
wave_enemies_alive :: proc(enemies: ^[MAX_ENEMIES]Enemy, enemy_count: int) -> bool {
	for i in 0 ..< enemy_count {
		e := &enemies[i]
		if e.wave_spawned && e.state != .Inactive {
			return true
		}
	}
	return false
}

@(private = "file")
is_platform_tile :: proc(map_data: ^dm.Dot_Map, tx, ty: int) -> bool {
	if ty < 0 || ty >= len(map_data.grid) {
		return false
	}
	row := map_data.grid[ty]
	if tx < 0 || tx >= len(row) {
		return false
	}
	sym := row[tx].symbol
	td, has := map_data.metadata[sym]
	return has && !td.passable && len(td.tiles) > 0
}

@(private = "file")
parse_positive_int :: proc(s: string, fallback: int) -> int {
	result := 0
	for ch in s {
		if ch < '0' || ch > '9' {
			continue
		}
		result = result * 10 + int(ch - '0')
	}
	if result <= 0 {
		return fallback
	}
	return result
}

@(private = "file")
parse_enemy_type_list :: proc(
	list: string,
	enemy_types: ^[MAX_WAVE_ENEMY_TYPES]Enemy_Type,
	count: ^int,
) {
	count^ = 0
	trimmed := strings.trim_space(list)
	if len(trimmed) >= 2 && trimmed[0] == '[' && trimmed[len(trimmed) - 1] == ']' {
		trimmed = trimmed[1:len(trimmed) - 1]
	}

	start := 0
	for i in 0 ..= len(trimmed) {
		if i != len(trimmed) && trimmed[i] != ',' {
			continue
		}
		name := strings.trim_space(trimmed[start:i])
		start = i + 1
		if len(name) == 0 || count^ >= MAX_WAVE_ENEMY_TYPES {
			continue
		}
		ok: bool
		enemy_types[count^], ok = enemy_type_from_name(name)
		if ok {
			count^ += 1
		}
	}
}

@(private = "file")
enemy_type_from_name :: proc(name: string) -> (Enemy_Type, bool) {
	switch name {
	case "enemy_cherub":
		return .Cherub, true
	case "enemy_ghoul":
		return .Ghoul, true
	case "enemy_mutant_cherub":
		return .Mutant_Cherub, true
	}
	return .Cherub, false
}

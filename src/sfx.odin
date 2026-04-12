package game

import "vendor:raylib"

Sfx_Id :: enum {
	Hit,
	Player_Footstep,
	Player_Jump,
	Player_Spear_Spawn,
	Player_Spear_Traveling,
	Player_Teleport,
	Player_Teleport_Slam_Impact,
	Enemy_Cherub_Attack,
	Enemy_Ghoul_Attack,
	Enemy_Mutant_Cherub_Aggroed,
	Enemy_Mutant_Cherub_Attack,
	Ui_Back,
	Ui_Confirm,
	Count,
}

SFX_COUNT :: int(Sfx_Id.Count)

@(private = "file")
sfx_sounds: [SFX_COUNT]raylib.Sound
@(private = "file")
sfx_loaded: [SFX_COUNT]bool

init_sfx :: proc() {
	if !raylib.IsAudioDeviceReady() {
		return
	}

	load_sfx(.Hit, "assets/audio/sfx/hit.wav", 0.65)
	load_sfx(.Player_Footstep, "assets/audio/sfx/player_footsteps.wav", 0.35)
	load_sfx(.Player_Jump, "assets/audio/sfx/player_jump.wav", 0.55)
	load_sfx(.Player_Spear_Spawn, "assets/audio/sfx/player_spear_spawns.wav", 0.65)
	load_sfx(.Player_Spear_Traveling, "assets/audio/sfx/player_spear_traveling.wav", 0.55)
	load_sfx(.Player_Teleport, "assets/audio/sfx/player_teleport.wav", 0.7)
	load_sfx(.Player_Teleport_Slam_Impact, "assets/audio/sfx/player_teleport_slam_impact.wav", 0.8)
	load_sfx(.Enemy_Cherub_Attack, "assets/audio/sfx/enemy_cherub_attack.wav", 0.65)
	load_sfx(.Enemy_Ghoul_Attack, "assets/audio/sfx/enemy_ghoul_attacks.wav", 0.7)
	load_sfx(.Enemy_Mutant_Cherub_Aggroed, "assets/audio/sfx/enemy_mutant_cherub_agroed.wav.wav", 0.65)
	load_sfx(.Enemy_Mutant_Cherub_Attack, "assets/audio/sfx/enemy_mutant_cherup_attack.wav", 0.7)
	load_sfx(.Ui_Back, "assets/audio/sfx/ui_back.wav", 0.6)
	load_sfx(.Ui_Confirm, "assets/audio/sfx/ui_confirm.wav", 0.6)
}

unload_sfx :: proc() {
	for i in 0 ..< SFX_COUNT {
		if sfx_loaded[i] {
			raylib.UnloadSound(sfx_sounds[i])
			sfx_loaded[i] = false
		}
	}
}

play_sfx :: proc(id: Sfx_Id) {
	idx := int(id)
	if idx < 0 || idx >= SFX_COUNT || !sfx_loaded[idx] {
		return
	}
	raylib.PlaySound(sfx_sounds[idx])
}

@(private = "file")
load_sfx :: proc(id: Sfx_Id, path: cstring, volume: f32) {
	idx := int(id)
	if idx < 0 || idx >= SFX_COUNT {
		return
	}

	sound := raylib.LoadSound(path)
	if !raylib.IsSoundValid(sound) {
		return
	}

	raylib.SetSoundVolume(sound, volume)
	sfx_sounds[idx] = sound
	sfx_loaded[idx] = true
}

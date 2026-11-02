extends Node
## All of ATHAR's sound in one place.
##
## Design rules, because this runs on a phone:
##   * four looping beds at most (day ambience, night ambience, rain, music) and
##     they cross-fade by volume instead of being created and destroyed;
##   * one-shots go through a small pool of players that are reused, so a hunt
##     cannot allocate audio nodes;
##   * everything that belongs to the deer is positional (AudioStreamPlayer3D on
##     the deer), so distance and direction come free from the engine;
##   * nothing is played when it cannot be heard: far-away animal calls are
##     skipped, and footsteps stop the moment the hunter stops.
##
## Every stream is one of the project's own generated files (see
## assets/audio/LICENSE.txt); nothing is downloaded and nothing is streamed.

const AudioSettings := preload("res://scripts/audio/audio_settings.gd")

const AUDIO_DIR := "res://assets/audio/"

## The ruined courtyard is the only stone surface in the world, so steps there
## use the stone set; the forest floor is a grass/soil mix and alternates both.
const RUIN_CENTER := Vector3(-10.0, 0.0, -15.0)
const RUIN_RADIUS := 6.0

const AMBIENCE_DAY_DB := -15.0
const AMBIENCE_NIGHT_DB := -14.0
const RAIN_DB := -11.0
const MUSIC_DB := -17.0

const STEP_DB := -9.0
const HOOF_DB := -13.0
const VOICE_DB := -7.0
const SFX_DB := -8.0

## One step every 0.33 s at the hunter's 4.4 m/s.
const STEP_INTERVAL := 0.33
const DEER_WALK_INTERVAL := 0.55
const DEER_RUN_INTERVAL := 0.22
## Animal calls are skipped beyond this, so no sound is played into empty forest.
const AUDIBLE_RANGE := 42.0
const FADE_DB_PER_SECOND := 26.0
const SILENT_DB := -60.0

const SFX_POOL_SIZE := 4

var settings: RefCounted

var _streams := {}
var _ambience_day: AudioStreamPlayer
var _ambience_night: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _music: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _deer_voice: AudioStreamPlayer3D
var _deer_steps: AudioStreamPlayer3D

var _day_target := AMBIENCE_DAY_DB
var _night_target := SILENT_DB
var _rain_target := SILENT_DB

var _step_timer := 0.0
var _hoof_timer := 0.0
var _step_side := 0
var _soil_phase := 0
var _sfx_cursor := 0
var _rng := RandomNumberGenerator.new()


func setup(audio_settings: RefCounted) -> void:
	settings = audio_settings
	_rng.seed = 1337
	_load_streams()

	_ambience_day = _make_bed("AmbienceDay", _streams["ambience_day"], AMBIENCE_DAY_DB)
	_ambience_night = _make_bed("AmbienceNight", _streams["ambience_night"], SILENT_DB)
	_rain = _make_bed("RainBed", _streams["rain"], SILENT_DB)
	_music = _make_bed("Music", _streams["music"], MUSIC_DB)
	_music.bus = "Music"

	for i in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "SFX%d" % i
		player.bus = "SFX"
		player.volume_db = SILENT_DB
		_release_on_exit(player)
		add_child(player)
		_sfx.append(player)

	if settings != null:
		settings.apply()


## The deer's voice and hooves follow the animal in 3D.
func attach_deer(deer: Node3D) -> void:
	if deer == null:
		return
	_deer_voice = _make_3d("DeerVoice", deer, VOICE_DB)
	_deer_steps = _make_3d("DeerSteps", deer, HOOF_DB)
	# Stop the animal's sounds the moment it leaves the tree, so nothing is still
	# playing when the game closes.
	deer.tree_exiting.connect(_silence_deer)


## Cross-fades the beds for the current hour and weather. Called only when the
## environment changes, not every frame.
func set_environment(night: float, rain: float, wind: float) -> void:
	var n := clampf(night, 0.0, 1.0)
	var r := clampf(rain, 0.0, 1.0)
	var w := clampf(wind, 0.0, 2.0)
	_day_target = AMBIENCE_DAY_DB if n < 0.5 else SILENT_DB
	_night_target = AMBIENCE_NIGHT_DB if n >= 0.5 else SILENT_DB
	# Wind is already in the ambience bed; a stronger wind lifts it slightly.
	_day_target += clampf((w - 1.0) * 2.0, -3.0, 3.0)
	if r > 0.02:
		_rain_target = RAIN_DB + clampf((r - 1.0) * 6.0, -6.0, 0.0)
	else:
		_rain_target = SILENT_DB


## Per-frame work: fade the beds, and run footsteps for hunter and deer.
func update(delta: float, hunter_position: Vector3, hunter_speed: float, deer_position: Vector3, deer_speed: float) -> void:
	_fade(_ambience_day, _day_target, delta)
	_fade(_ambience_night, _night_target, delta)
	_fade(_rain, _rain_target, delta)
	_fade(_music, MUSIC_DB, delta)

	_update_footsteps(delta, hunter_position, hunter_speed)
	_update_hooves(delta, hunter_position, deer_position, deer_speed)


func _update_footsteps(delta: float, hunter_position: Vector3, speed: float) -> void:
	if speed < 0.4:
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer > 0.0:
		return
	_step_timer = STEP_INTERVAL
	play_step(surface_at(hunter_position))


## Which material the hunter is walking on: stone inside the ruin, otherwise the
## forest floor, which alternates grass and soil because the ground texture is a
## mix of both.
func surface_at(position: Vector3) -> String:
	if Vector2(position.x - RUIN_CENTER.x, position.z - RUIN_CENTER.z).length() <= RUIN_RADIUS:
		return "stone"
	_soil_phase += 1
	return "soil" if _soil_phase % 4 == 0 else "grass"


func play_step(surface: String) -> void:
	if surface == "stone":
		_step_side = (_step_side + 1) % 2
		_play(_streams["step_stone"][_step_side], STEP_DB, 1.0)
	elif surface == "soil":
		_step_side = (_step_side + 1) % 2
		_play(_streams["step_soil"][_step_side], STEP_DB, 1.0)
	else:
		_step_side = (_step_side + 1) % 3
		_play(_streams["step_grass"][_step_side], STEP_DB, 1.0)


func _update_hooves(delta: float, hunter_position: Vector3, deer_position: Vector3, speed: float) -> void:
	if speed < 0.5 or _deer_steps == null:
		_hoof_timer = 0.0
		return
	if deer_position.distance_to(hunter_position) > AUDIBLE_RANGE:
		return
	_hoof_timer -= delta
	if _hoof_timer > 0.0:
		return
	_hoof_timer = DEER_RUN_INTERVAL if speed > 3.0 else DEER_WALK_INTERVAL
	_deer_steps.stream = _streams["hoof"][_step_side % 2]
	_deer_steps.pitch_scale = _rng.randf_range(0.94, 1.06)
	_deer_steps.play()


## Warning snort. Skipped when the animal is too far away to be heard.
func play_deer_alert() -> void:
	if _deer_voice == null:
		return
	_deer_voice.stream = _streams["deer_alert"]
	_deer_voice.pitch_scale = _rng.randf_range(0.96, 1.04)
	_deer_voice.play()


func play_deer_flee() -> void:
	if _deer_voice == null:
		return
	_deer_voice.stream = _streams["deer_flee"]
	_deer_voice.pitch_scale = _rng.randf_range(0.97, 1.05)
	_deer_voice.play()


func play_capture() -> void:
	_play(_streams["capture"], SFX_DB - 2.0)


func play_ui_tap() -> void:
	_play(_streams["ui_tap"], SFX_DB - 6.0)


## Number of audio players the director owns, used by the performance test.
func player_count() -> int:
	return 4 + _sfx.size() + (2 if _deer_voice != null else 0)


func is_playing(name: String) -> bool:
	for player in _sfx:
		if player.name == name and player.playing:
			return true
	return false


# ---------------------------------------------------------------- internals ---
func _load_streams() -> void:
	_streams["ambience_day"] = _loop(AUDIO_DIR + "ambience_day.wav")
	_streams["ambience_night"] = _loop(AUDIO_DIR + "ambience_night.wav")
	_streams["rain"] = _loop(AUDIO_DIR + "rain_loop.wav")
	_streams["music"] = _loop(AUDIO_DIR + "music_ambient.wav")
	_streams["step_grass"] = [
		load(AUDIO_DIR + "step_grass_1.wav"),
		load(AUDIO_DIR + "step_grass_2.wav"),
		load(AUDIO_DIR + "step_grass_3.wav"),
	]
	_streams["step_soil"] = [
		load(AUDIO_DIR + "step_soil_1.wav"),
		load(AUDIO_DIR + "step_soil_2.wav"),
	]
	_streams["step_stone"] = [
		load(AUDIO_DIR + "step_stone_1.wav"),
		load(AUDIO_DIR + "step_stone_2.wav"),
	]
	_streams["hoof"] = [
		load(AUDIO_DIR + "hoof_1.wav"),
		load(AUDIO_DIR + "hoof_2.wav"),
	]
	_streams["deer_alert"] = load(AUDIO_DIR + "deer_alert.wav")
	_streams["deer_flee"] = load(AUDIO_DIR + "deer_flee.wav")
	_streams["capture"] = load(AUDIO_DIR + "capture.wav")
	_streams["ui_tap"] = load(AUDIO_DIR + "ui_tap.wav")


## Loads a looping bed. The import leaves loops off, so the stream is duplicated
## and marked to loop over its whole length; duplicating keeps the shared cached
## resource untouched.
func _loop(path: String) -> AudioStreamWAV:
	var source: AudioStreamWAV = load(path)
	if source == null:
		push_warning("ATHAR audio: missing %s" % path)
		return null
	var stream: AudioStreamWAV = source.duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream


func _make_bed(node_name: String, stream: AudioStream, level_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = "SFX"
	player.stream = stream
	player.volume_db = level_db
	_release_on_exit(player)
	add_child(player)
	if stream != null:
		player.play()
	return player


## Stops a player and drops its stream when it leaves the tree. Each player does
## this for itself rather than relying on the director, because the director and
## the deer can be freed in either order; a stream still playing at shutdown is
## reported by Godot as a leaked resource.
func _release_on_exit(player: Node) -> void:
	player.tree_exiting.connect(func() -> void:
		if player is AudioStreamPlayer:
			(player as AudioStreamPlayer).stop()
			(player as AudioStreamPlayer).stream = null
		elif player is AudioStreamPlayer3D:
			(player as AudioStreamPlayer3D).stop()
			(player as AudioStreamPlayer3D).stream = null)


func _make_3d(node_name: String, parent: Node3D, level_db: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	parent.add_child(player)
	player.bus = "SFX"
	player.volume_db = level_db
	player.unit_size = 9.0
	player.max_distance = AUDIBLE_RANGE
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.panning_strength = 1.0
	_release_on_exit(player)
	return player


func _play(stream: AudioStream, level_db: float, pitch := 1.0) -> void:
	if stream == null or _sfx.is_empty():
		return
	var player := _sfx[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx.size()
	player.stream = stream
	player.volume_db = level_db
	player.pitch_scale = pitch * _rng.randf_range(0.97, 1.03)
	player.play()


## Releases every stream on the way out. Without this, a sound that is still
## playing when the game closes keeps its WAV alive and Godot reports a leaked
## resource at exit.
func _exit_tree() -> void:
	for player in _all_players():
		player.stop()
		player.stream = null


func _silence_deer() -> void:
	for player in [_deer_voice, _deer_steps]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_deer_voice = null
	_deer_steps = null


func _all_players() -> Array[Node]:
	var players: Array[Node] = [_ambience_day, _ambience_night, _rain, _music]
	players.append_array(_sfx)
	if is_instance_valid(_deer_voice):
		players.append(_deer_voice)
	if is_instance_valid(_deer_steps):
		players.append(_deer_steps)
	return players.filter(func(player: Node) -> bool: return player != null)


func _fade(player: AudioStreamPlayer, target_db: float, delta: float) -> void:
	if player == null:
		return
	if is_equal_approx(player.volume_db, target_db):
		return
	player.volume_db = move_toward(player.volume_db, target_db, FADE_DB_PER_SECOND * delta)

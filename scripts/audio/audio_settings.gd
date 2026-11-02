extends RefCounted
## Volume and mute settings for ATHAR.
##
## The project had no save system, so this adds the smallest one that meets the
## brief: an audio-only ConfigFile under `user://`. It is deliberately separate
## from gameplay (nothing else is persisted), and the path is injectable so tests
## can round-trip a temporary file instead of touching the player's settings.
##
## Levels are 0..1 linear gains, applied to the Master, Music and SFX buses that
## `audio/default_bus_layout.tres` defines. Muting is a bus mute, not a volume of
## zero, so the slider positions survive a mute/unmute.

const DEFAULT_PATH := "user://audio_settings.cfg"
const SECTION := "audio"

const DEFAULT_MASTER := 0.90
const DEFAULT_MUSIC := 0.55
const DEFAULT_EFFECTS := 0.85

## Below this the bus is treated as silent rather than at -inf dB.
const SILENT := 0.0001

var master := DEFAULT_MASTER
var music := DEFAULT_MUSIC
var effects := DEFAULT_EFFECTS
var muted := false

var _path := DEFAULT_PATH


func _init(path := DEFAULT_PATH) -> void:
	_path = path


## Reads saved settings if the file exists. Returns true when anything loaded.
func load_settings() -> bool:
	var config := ConfigFile.new()
	if config.load(_path) != OK:
		return false
	master = clampf(float(config.get_value(SECTION, "master", master)), 0.0, 1.0)
	music = clampf(float(config.get_value(SECTION, "music", music)), 0.0, 1.0)
	effects = clampf(float(config.get_value(SECTION, "effects", effects)), 0.0, 1.0)
	muted = bool(config.get_value(SECTION, "muted", muted))
	apply()
	return true


func save() -> bool:
	var config := ConfigFile.new()
	config.set_value(SECTION, "master", master)
	config.set_value(SECTION, "music", music)
	config.set_value(SECTION, "effects", effects)
	config.set_value(SECTION, "muted", muted)
	return config.save(_path) == OK


func set_master(value: float) -> void:
	master = clampf(value, 0.0, 1.0)
	apply()


func set_music(value: float) -> void:
	music = clampf(value, 0.0, 1.0)
	apply()


func set_effects(value: float) -> void:
	effects = clampf(value, 0.0, 1.0)
	apply()


func set_muted(value: bool) -> void:
	muted = value
	apply()


func toggle_mute() -> bool:
	muted = not muted
	apply()
	return muted


func reset() -> void:
	master = DEFAULT_MASTER
	music = DEFAULT_MUSIC
	effects = DEFAULT_EFFECTS
	muted = false
	apply()


## Pushes the levels into the audio server. Safe to call before the buses exist.
func apply() -> void:
	_set_bus_volume("Master", master)
	_set_bus_volume("Music", music)
	_set_bus_volume("SFX", effects)
	var master_index := AudioServer.get_bus_index("Master")
	if master_index >= 0:
		AudioServer.set_bus_mute(master_index, muted)


func is_silent() -> bool:
	return muted or master <= 0.0


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, SILENT)))

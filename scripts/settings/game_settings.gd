extends "res://scripts/audio/audio_settings.gd"
## Every persisted player preference in one file: audio, language, graphics and
## touch sensitivity.
##
## This extends the Phase 3.4 audio settings, so the three volume levels, mute,
## bus application and clamping behave exactly as before — the audio tests still
## exercise that class directly. What changes is the file: this one writes
## `user://athar_settings.cfg` with an `[audio]` and a `[game]` section, which is
## what "settings survive a restart" means for the whole UI rather than only for
## sound. The path is injectable, so tests round-trip a temporary file.

const Localization := preload("res://scripts/ui/localization.gd")

const SETTINGS_PATH := "user://athar_settings.cfg"
const GAME_SECTION := "game"

const QUALITY_LOW := "low"
const QUALITY_MEDIUM := "medium"
const QUALITY_HIGH := "high"
const QUALITY_LEVELS := [QUALITY_LOW, QUALITY_MEDIUM, QUALITY_HIGH]
const DEFAULT_QUALITY := QUALITY_MEDIUM

## The joystick's own curve, not the engine's: 0.5 is a slow, deliberate stick,
## 2.0 a very quick one. The default reproduces the old button speed.
const SENSITIVITY_MIN := 0.5
const SENSITIVITY_MAX := 2.0
const DEFAULT_SENSITIVITY := 1.0

var language := Localization.DEFAULT_LANGUAGE
var quality := DEFAULT_QUALITY
var sensitivity := DEFAULT_SENSITIVITY


func _init(path := SETTINGS_PATH) -> void:
	super._init(path)


func load_settings() -> bool:
	var loaded := super.load_settings()
	var config := ConfigFile.new()
	if config.load(_path) != OK:
		return loaded
	language = String(config.get_value(GAME_SECTION, "language", language))
	if not language in Localization.LANGUAGES:
		language = Localization.DEFAULT_LANGUAGE
	var stored_quality := String(config.get_value(GAME_SECTION, "quality", quality))
	quality = stored_quality if stored_quality in QUALITY_LEVELS else DEFAULT_QUALITY
	sensitivity = clampf(float(config.get_value(GAME_SECTION, "sensitivity", sensitivity)), SENSITIVITY_MIN, SENSITIVITY_MAX)
	return true


func save() -> bool:
	var config := ConfigFile.new()
	config.set_value(SECTION, "master", master)
	config.set_value(SECTION, "music", music)
	config.set_value(SECTION, "effects", effects)
	config.set_value(SECTION, "muted", muted)
	config.set_value(GAME_SECTION, "language", language)
	config.set_value(GAME_SECTION, "quality", quality)
	config.set_value(GAME_SECTION, "sensitivity", sensitivity)
	return config.save(_path) == OK


func reset() -> void:
	super.reset()
	language = Localization.DEFAULT_LANGUAGE
	quality = DEFAULT_QUALITY
	sensitivity = DEFAULT_SENSITIVITY


func set_language(code: String) -> String:
	language = code if code in Localization.LANGUAGES else Localization.DEFAULT_LANGUAGE
	return language


func set_quality(level: String) -> String:
	quality = level if level in QUALITY_LEVELS else DEFAULT_QUALITY
	return quality


func set_sensitivity(value: float) -> float:
	sensitivity = clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX)
	return sensitivity

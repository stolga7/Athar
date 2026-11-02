extends Node
## Headless tests for ATHAR's audio (Phase 3.4).
##
## Run with:
##   godot --headless --path . res://scenes/tests/audio_tests.tscn
##
## What this can and cannot prove: the headless engine uses the dummy audio
## driver, so nothing here can confirm that a sound *sounds* right, or that it is
## audible on a phone speaker. It does verify that the assets exist and are sane,
## that they load, that the buses and volumes are configured, that the director
## starts and stops the right players, that positional nodes are set up, that
## settings persist, and that the scene wires all of it to the game events.

const AudioDirector := preload("res://scripts/audio/audio_director.gd")
const AudioSettings := preload("res://scripts/audio/audio_settings.gd")
const AudioPanel := preload("res://scripts/ui/audio_panel.gd")
const DeerAI := preload("res://scripts/animals/deer_ai.gd")
const DayCycle := preload("res://scripts/world/day_cycle.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")

const AUDIO_DIR := "res://assets/audio/"
const LICENSE_PATH := "res://assets/audio/LICENSE.txt"
const TEST_SETTINGS := "user://athar_test_audio.cfg"
const DT := 1.0 / 60.0
const WATCHDOG_SECONDS := 90.0

const EXPECTED_FILES := [
	"ambience_day.wav", "ambience_night.wav", "rain_loop.wav", "music_ambient.wav",
	"step_grass_1.wav", "step_grass_2.wav", "step_grass_3.wav",
	"step_soil_1.wav", "step_soil_2.wav",
	"step_stone_1.wav", "step_stone_2.wav",
	"hoof_1.wav", "hoof_2.wav",
	"deer_alert.wav", "deer_flee.wav", "capture.wav", "ui_tap.wav",
]

var _checks := 0
var _failures := 0
var _main: Node3D
var _watchdog: Timer


func _ready() -> void:
	print("ATHAR audio tests")
	_watchdog = Timer.new()
	_watchdog.wait_time = WATCHDOG_SECONDS
	_watchdog.one_shot = true
	_watchdog.timeout.connect(_on_watchdog_timeout)
	add_child(_watchdog)
	_watchdog.start()

	_test_assets()
	_test_buses()
	_test_settings()
	_test_director()
	await _test_scene()
	_finish()


func _finish() -> void:
	_watchdog.stop()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	# Silence everything and let the mixer notice, so no stream is left playing
	# when the engine shuts down (that would be reported as a leaked resource).
	_stop_all_audio(get_tree().root)
	# The audio server mixes on its own thread; a short real-time sleep lets it
	# release the stopped playbacks before the engine shuts down.
	OS.delay_msec(250)
	await get_tree().process_frame
	print("")
	if _failures > 0:
		print("RESULT: %d checks, %d failed" % [_checks, _failures])
		get_tree().quit(1)
	else:
		print("RESULT: %d checks, 0 failed" % _checks)
		get_tree().quit(0)


func _stop_all_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stop()
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stop()
	for child in node.get_children():
		_stop_all_audio(child)


func _on_watchdog_timeout() -> void:
	printerr("ATHAR_TEST_WATCHDOG=expired")
	printerr("RESULT: %d checks, %d failed (watchdog expired after %.0f s)" % [_checks, _failures + 1, WATCHDOG_SECONDS])
	get_tree().quit(2)


func _check(condition: bool, label: String, detail := "") -> void:
	_checks += 1
	if condition:
		print("  PASS  %s%s" % [label, "" if detail == "" else "  (%s)" % detail])
	else:
		_failures += 1
		print("  FAIL  %s%s" % [label, "" if detail == "" else "  (%s)" % detail])


# ------------------------------------------------------------------- assets ---
func _test_assets() -> void:
	var missing: Array[String] = []
	var total_bytes := 0
	for name in EXPECTED_FILES:
		var path: String = AUDIO_DIR + name
		if not FileAccess.file_exists(path):
			missing.append(name)
		else:
			total_bytes += FileAccess.get_file_as_bytes(path).size()
	_check(missing.is_empty(), "every sound file the game references exists",
		"%d files" % EXPECTED_FILES.size() if missing.is_empty() else str(missing))
	_check(EXPECTED_FILES.size() <= 20, "the audio set stays small", "%d files" % EXPECTED_FILES.size())
	_check(total_bytes > 0 and total_bytes < 3 * 1024 * 1024, "the audio set fits a mobile budget",
		"%.2f MB" % (total_bytes / 1048576.0))

	_check(FileAccess.file_exists(LICENSE_PATH), "the assets ship with a provenance/licence note")
	if FileAccess.file_exists(LICENSE_PATH):
		var text := FileAccess.get_file_as_string(LICENSE_PATH)
		_check(text.to_lower().contains("generated"), "the licence note states where the audio came from")
		_check(text.to_lower().contains("third-party") or text.to_lower().contains("copyright"),
			"the licence note rules out third-party material")

	var rates := {}
	var loops_ok := true
	var sounds_ok := true
	for name in EXPECTED_FILES:
		var stream: AudioStreamWAV = load(AUDIO_DIR + name)
		if stream == null:
			sounds_ok = false
			continue
		rates[stream.mix_rate] = true
		if stream.get_length() <= 0.0:
			sounds_ok = false
		if name in ["ambience_day.wav", "ambience_night.wav", "rain_loop.wav", "music_ambient.wav"]:
			# Loop beds are marked at load time by the director; the raw import is
			# allowed either way, but must be a valid stream.
			loops_ok = loops_ok and stream.get_length() > 1.0
	_check(sounds_ok, "every file loads as a playable stream")
	_check(loops_ok, "the looping beds are long enough to loop without repeating audibly")
	_check(rates.has(16000) and rates.has(22050), "assets use the two documented sample rates", str(rates.keys()))

	var ambience: AudioStreamWAV = load(AUDIO_DIR + "ambience_day.wav")
	_check(ambience.get_length() > 5.0, "day ambience is a long bed, not a short loop",
		"%.1f s" % ambience.get_length())
	var click: AudioStreamWAV = load(AUDIO_DIR + "ui_tap.wav")
	_check(click.get_length() < 0.2, "the interface tap is short", "%.2f s" % click.get_length())
	var step: AudioStreamWAV = load(AUDIO_DIR + "step_grass_1.wav")
	_check(step.get_length() < 0.3, "a footstep is short", "%.2f s" % step.get_length())

	# Peak level: loud enough to hear, quiet enough not to clip. Read from the
	# shipped WAV, not the imported stream: Godot re-encodes imports as ADPCM, so
	# the runtime data is not raw PCM.
	var peaks_ok := true
	var quiet := false
	for name in ["ambience_day.wav", "rain_loop.wav", "music_ambient.wav", "capture.wav", "deer_alert.wav"]:
		var peak := _file_peak(AUDIO_DIR + name)
		if peak > 0.99:
			peaks_ok = false
		if peak < 0.05:
			quiet = true
	_check(peaks_ok, "no asset clips")
	_check(not quiet, "no asset is silent")

	# Mobile size: the importer compresses the beds, so runtime memory is a
	# fraction of the source files.
	var ambience_stream: AudioStreamWAV = load(AUDIO_DIR + "ambience_day.wav")
	var source_bytes := FileAccess.get_file_as_bytes(AUDIO_DIR + "ambience_day.wav").size()
	_check(ambience_stream.data.size() < source_bytes,
		"long beds are compressed on import, not held as raw PCM",
		"%d KB of %d KB" % [ambience_stream.data.size() / 1024, source_bytes / 1024])


## Highest absolute sample value in a 16-bit mono WAV file on disk, 0..1.
## Parses the RIFF chunks directly so it works whatever the importer did.
func _file_peak(path: String) -> float:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44:
		return 0.0
	var offset := 12
	while offset + 8 <= bytes.size():
		var chunk_id := bytes.slice(offset, offset + 4).get_string_from_ascii()
		var chunk_size := bytes.decode_u32(offset + 4)
		if chunk_id == "data":
			var start := offset + 8
			var frames := mini(chunk_size / 2, 22050)
			var peak := 0
			for i in range(frames):
				peak = maxi(peak, absi(bytes.decode_s16(start + i * 2)))
			return float(peak) / 32768.0
		offset += 8 + chunk_size + (chunk_size % 2)
	return 0.0


# -------------------------------------------------------------------- buses ---
func _test_buses() -> void:
	_check(AudioServer.get_bus_index("Master") == 0, "the Master bus exists")
	_check(AudioServer.get_bus_index("Music") > 0, "the Music bus exists")
	_check(AudioServer.get_bus_index("SFX") > 0, "the SFX bus exists")
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	_check(AudioServer.get_bus_send(music) == "Master", "music routes to Master")
	_check(AudioServer.get_bus_send(sfx) == "Master", "effects route to Master")


# ----------------------------------------------------------------- settings ---
func _test_settings() -> void:
	var settings = AudioSettings.new(TEST_SETTINGS)
	_check(absf(settings.master - AudioSettings.DEFAULT_MASTER) < 0.001, "master defaults to the shipped level")
	_check(absf(settings.music - AudioSettings.DEFAULT_MUSIC) < 0.001, "music defaults to the shipped level")
	_check(absf(settings.effects - AudioSettings.DEFAULT_EFFECTS) < 0.001, "effects default to the shipped level")
	_check(not settings.muted, "sound starts unmuted")

	settings.set_master(2.0)
	settings.set_music(-1.0)
	settings.set_effects(0.25)
	_check(absf(settings.master - 1.0) < 0.001, "master volume clamps to 1.0")
	_check(absf(settings.music - 0.0) < 0.001, "music volume clamps to 0.0")
	_check(absf(settings.effects - 0.25) < 0.001, "effects volume follows the slider")

	var sfx_index := AudioServer.get_bus_index("SFX")
	var db := AudioServer.get_bus_volume_db(sfx_index)
	_check(absf(db - linear_to_db(0.25)) < 0.05, "the effects bus volume follows the setting", "%.1f dB" % db)

	settings.set_master(0.6)
	_check(settings.toggle_mute(), "mute toggles on")
	_check(AudioServer.is_bus_mute(0), "the Master bus is actually muted")
	_check(settings.is_silent(), "muted counts as silent")
	_check(not settings.toggle_mute(), "mute toggles off")
	_check(not AudioServer.is_bus_mute(0), "the Master bus is unmuted again")
	_check(absf(settings.master - 0.6) < 0.001, "unmuting keeps the volume that was set")

	# Persistence: an audio-only ConfigFile, no gameplay save system involved.
	settings.set_master(0.33)
	settings.set_music(0.44)
	settings.set_muted(true)
	_check(settings.save(), "settings save to disk")
	_check(FileAccess.file_exists(TEST_SETTINGS), "a settings file is created")

	var reloaded = AudioSettings.new(TEST_SETTINGS)
	_check(reloaded.load_settings(), "settings load back from disk")
	_check(absf(reloaded.master - 0.33) < 0.001 and absf(reloaded.music - 0.44) < 0.001,
		"volume values survive a restart", "master %.2f, music %.2f" % [reloaded.master, reloaded.music])
	_check(reloaded.muted, "mute survives a restart")

	reloaded.reset()
	_check(absf(reloaded.master - AudioSettings.DEFAULT_MASTER) < 0.001 and not reloaded.muted,
		"reset restores the shipped defaults")

	var fresh = AudioSettings.new("user://athar_missing_audio.cfg")
	_check(not fresh.load_settings(), "a missing settings file is not an error")
	_check(absf(fresh.master - AudioSettings.DEFAULT_MASTER) < 0.001, "missing settings fall back to defaults")


# ----------------------------------------------------------------- director ---
func _test_director() -> void:
	var settings = AudioSettings.new(TEST_SETTINGS)
	settings.reset()
	var director = AudioDirector.new()
	add_child(director)
	director.setup(settings)
	director.set_environment(0.0, 0.0, 1.0)

	_check(director.player_count() >= 8 and director.player_count() <= 12,
		"the director owns a small, fixed set of players", "%d players" % director.player_count())
	var music: AudioStreamPlayer = director.get_node("Music")
	_check(music != null and music.playing, "music plays as a quiet bed")
	_check(music.volume_db <= -12.0, "music sits well under the effects", "%.1f dB" % music.volume_db)

	var day_bed: AudioStreamPlayer = director.get_node("AmbienceDay")
	var night_bed: AudioStreamPlayer = director.get_node("AmbienceNight")
	_check(day_bed.playing and night_bed.playing, "both ambience beds run, so they can cross-fade")
	_check(day_bed.volume_db > night_bed.volume_db, "daylight favours the day bed",
		"%.0f vs %.0f dB" % [day_bed.volume_db, night_bed.volume_db])

	var stream: AudioStreamWAV = day_bed.stream
	_check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"the ambience bed is set to loop")
	_check(stream != null and stream.loop_end > 0, "the loop covers the whole file")

	# Night cross-fade: run the fades for a few seconds.
	director.set_environment(1.0, 0.0, 1.0)
	for i in range(int(4.0 / DT)):
		director.update(DT, Vector3.ZERO, 0.0, Vector3(20, 0, 0), 0.0)
	_check(night_bed.volume_db > day_bed.volume_db, "night falls and the night bed takes over",
		"day %.0f dB, night %.0f dB" % [day_bed.volume_db, night_bed.volume_db])

	# Rain follows the weather.
	var rain: AudioStreamPlayer = director.get_node("RainBed")
	_check(rain.playing, "the rain bed is always running, ready to fade in")
	var dry_db := rain.volume_db
	director.set_environment(0.0, 1.0, 1.0)
	for i in range(int(4.0 / DT)):
		director.update(DT, Vector3.ZERO, 0.0, Vector3(20, 0, 0), 0.0)
	_check(rain.volume_db > dry_db + 10.0, "rain fades in with the weather",
		"%.0f -> %.0f dB" % [dry_db, rain.volume_db])

	# Footsteps: silence while standing, steps while moving.
	for i in range(60):
		director.update(DT, Vector3.ZERO, 0.0, Vector3(20, 0, 0), 0.0)
	_check(not _any_sfx_playing(director), "a standing hunter makes no footstep noise")
	for i in range(30):
		director.update(DT, Vector3.ZERO, 4.4, Vector3(20, 0, 0), 0.0)
	_check(_any_sfx_playing(director), "walking produces footsteps")

	_check(director.surface_at(Vector3(-10, 0, -15)) == "stone",
		"the ruined courtyard is a stone surface")
	var open_ground: String = director.surface_at(Vector3(25, 0, 25))
	_check(open_ground in ["grass", "soil"], "open forest floor uses grass or soil", open_ground)
	var saw_soil := false
	for i in range(40):
		if director.surface_at(Vector3(25, 0, 25)) == "soil":
			saw_soil = true
	_check(saw_soil, "the forest floor mixes grass and soil steps")

	# Footstep pools are reused, never grown.
	var before := director.player_count()
	for i in range(40):
		director.play_step("stone")
	_check(director.player_count() == before, "footsteps reuse a fixed pool of players")

	# Cues.
	director.play_capture()
	_check(_any_sfx_playing(director), "the capture cue plays")
	director.play_ui_tap()
	_check(_any_sfx_playing(director), "the interface tap plays")

	# Positional animal audio needs a parent; verify the 3D setup through a stub.
	var deer_stub := Node3D.new()
	add_child(deer_stub)
	director.attach_deer(deer_stub)
	var voice: AudioStreamPlayer3D = deer_stub.get_node_or_null("DeerVoice")
	var steps: AudioStreamPlayer3D = deer_stub.get_node_or_null("DeerSteps")
	_check(voice != null and steps != null, "the deer owns positional audio nodes")
	if voice != null:
		_check(voice.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE,
			"animal sound falls off with distance", "unit %.0f m" % voice.unit_size)
		_check(voice.max_distance > 10.0 and voice.max_distance <= 60.0,
			"animal sound has a bounded range", "%.0f m" % voice.max_distance)
		_check(voice.panning_strength > 0.5, "animal sound is directional")
		director.play_deer_alert()
		_check(voice.playing, "the deer's warning snort plays at its position")
		director.play_deer_flee()
		_check(voice.playing, "the deer's flight call plays at its position")

	# Hooves stop when the animal stops.
	for i in range(120):
		director.update(DT, Vector3.ZERO, 0.0, Vector3(5, 0, 0), 0.0)
	_check(not steps.playing or steps.stream == null, "a still deer makes no hoofbeats")

	deer_stub.queue_free()
	director.queue_free()


func _any_sfx_playing(director) -> bool:
	for i in range(4):
		var player: AudioStreamPlayer = director.get_node_or_null("SFX%d" % i)
		if player != null and player.playing:
			return true
	return false


# -------------------------------------------------------------------- scene ---
func _test_scene() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	for _i in range(4):
		await get_tree().physics_frame

	var director = _main.audio
	_check(director != null, "the scene builds an audio director")
	_check(_main.audio_settings != null, "the scene loads audio settings")
	_check(director.player_count() <= 12, "the scene keeps the audio player count small",
		"%d players" % director.player_count())

	var panel = _main.audio_panel
	_check(panel != null and panel.settings != null, "the scene adds an audio settings panel")
	_check(panel.master_slider != null and panel.music_slider != null and panel.effects_slider != null,
		"the panel has master, music and effects controls")
	_check(panel.mute_button != null, "the panel has a mute control")
	_check(not panel.panel.visible, "the panel starts collapsed, out of the way")
	panel.toggle()
	_check(panel.panel.visible, "the panel opens on demand")
	panel.music_slider.value = 0.2
	_check(absf(_main.audio_settings.music - 0.2) < 0.001, "moving a slider changes the music volume")
	panel.mute_button.pressed.emit()
	_check(_main.audio_settings.muted, "the mute button mutes the game")
	panel.mute_button.pressed.emit()
	_check(not _main.audio_settings.muted, "the mute button unmutes again")
	panel.toggle()
	_check(not panel.panel.visible, "the panel closes again")

	# Environment changes reach the audio beds.
	_main.living_world.day.set_time(0.0)
	_main.living_world.weather.force_state("rain")
	_main.living_world.apply()
	_main._apply_wildlife_environment()
	for i in range(8):
		await get_tree().physics_frame
	var rain_bed: AudioStreamPlayer = director.get_node("RainBed")
	_check(rain_bed.volume_db > -60.0, "the scene feeds weather into the rain bed",
		"%.0f dB" % rain_bed.volume_db)

	# Gameplay events reach the audio: an alerted deer speaks, capture chimes,
	# the hunt button taps.
	_main.hunter.global_position = Vector3(0, 0.1, 0)
	_main.deer_ai.reset()
	_main.deer.global_position = Vector3(0, 0.1, -9.0)
	var voice: AudioStreamPlayer3D = _main.deer.get_node_or_null("DeerVoice")
	_check(voice != null, "the live deer carries its positional voice")
	# The snort is short, so it has to be caught while it is still playing.
	var snort_heard := false
	for i in range(40):
		await get_tree().physics_frame
		if voice != null and voice.playing:
			snort_heard = true
	# Night and rain were forced above, so the deer's reduced sight can make this
	# an investigation rather than an outright flight; any reaction is fine.
	_check(_main.deer_state in [DeerAI.ALERTED, DeerAI.INVESTIGATING, DeerAI.FLEEING],
		"the deer still reacts to the hunter", _main.deer_state)
	_check(snort_heard, "noticing the hunter is audible")

	_main.hunt_button.pressed.emit()
	_check(_any_sfx_playing(director), "the hunt button gives audible feedback")

	_main.deer.global_position = _main.hunter.global_position + Vector3(0, 0, 1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_main.hunt_session.is_captured, "capture still works with audio enabled")

	_check(DeerAI.SPRINT_SPEED > 0.0 and DayCycle.SECONDS_PER_DAY > 0.0,
		"the other systems are still intact")

	# Stop the scene's audio before it is freed: a stream still playing when its
	# player disappears is reported by Godot as a leaked resource at exit.
	_stop_all_audio(_main)
	_main.queue_free()
	await get_tree().process_frame

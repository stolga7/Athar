extends Node3D

# ATHAR vertical slice: procedural wilderness, touch controls, hunter and reactive deer.
#
# Phase 3 split the original single script into focused pieces:
#   scripts/visuals/hunter_rig.gd   hunter mesh + animation
#   scripts/visuals/deer_rig.gd     deer mesh + animation
#   scripts/animals/deer_ai.gd      deer detection/state machine (pure logic)
#   scripts/gameplay/hunt_session.gd capture bookkeeping and the hunt loop
# This file keeps world generation, movement, camera and HUD, exactly as before.

const HunterRig := preload("res://scripts/visuals/hunter_rig.gd")
const DeerRig := preload("res://scripts/visuals/deer_rig.gd")
const DeerAI := preload("res://scripts/animals/deer_ai.gd")
const HuntSession := preload("res://scripts/gameplay/hunt_session.gd")
const CameraRig := preload("res://scripts/visuals/camera_rig.gd")
const Forest := preload("res://scripts/visuals/forest.gd")
const WildsGround := preload("res://scripts/visuals/wilds_ground.gd")
const WildsEnvironment := preload("res://scripts/visuals/wilds_environment.gd")
const LivingWorld := preload("res://scripts/world/living_world.gd")
const AudioDirector := preload("res://scripts/audio/audio_director.gd")
const GameSettings := preload("res://scripts/settings/game_settings.gd")
const GraphicsProfile := preload("res://scripts/settings/graphics_profile.gd")
const RegionManager := preload("res://scripts/world/region_manager.gd")
const RegionDefinition := preload("res://scripts/world/region_definition.gd")
const Localization := preload("res://scripts/ui/localization.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const MAIN_MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const SETTINGS_MENU_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const REGION_MENU_SCENE := preload("res://scenes/ui/region_menu.tscn")
const CONFIRM_SCENE := preload("res://scenes/ui/confirm_prompt.tscn")

const WORLD_SIZE := 90.0
const GRAVITY := 20.0

## Hunter movement, tuned against the deer's speeds in deer_ai.gd: faster than a
## tired deer (3.4) and slower than a fresh one (5.6).
const HUNTER_SPEED := 4.4
const HUNTER_BRAKE := 18.0
const HUNTER_TURN_RATE := 8.0
const HUNTER_LIMIT := 43.0
const DEER_LIMIT := 41.0
## Where a freshly started hunt drops the deer, measured from the hunter.
const NEW_HUNT_MIN_DISTANCE := 16.0
const NEW_HUNT_MAX_DISTANCE := 26.0
## How close the hunter must stand to a region's gate for the travel prompt.
const GATE_RADIUS := 3.2

var hunter: CharacterBody3D
var deer: CharacterBody3D
var hunter_rig: Node3D
var deer_rig: Node3D
var deer_ai: DeerAI
var hunt_session: HuntSession
var deer_collider: CollisionShape3D
var camera: Camera3D
var camera_rig: CameraRig
var deer_marker: Control
## Clock, weather, wind and rain. Owns the day/night and weather state and
## pushes it into the environment, the ground and the deer's senses.
var living_world: LivingWorld
## Sound: ambience, footsteps, animal calls, capture cue and the volume panel.
var audio: AudioDirector
var audio_settings: RefCounted
var audio_panel: Control
var hud_root: Control
## Planar speed of each actor, used for footstep timing.
var deer_speed := 0.0
## Summary dictionaries from the visual builders, used by the visual tests.
var forest_info := {}
var ground_info := {}
var environment_info := {}
var status_label: Label
var info_label: Label
var move_vector := Vector2.ZERO
var stamina := 100.0
var hunt_button: Button
## The HUD scene, its layer, and the menu layer that sits above it.
var hud: Control
var hud_layer: CanvasLayer
var menu_layer: CanvasLayer
var main_menu: Control
var pause_menu: Control
var settings_menu: Control
var confirm_prompt: Control
## Screen-space direction asked for by the movement pad, -1..1 per axis.
var joystick_vector := Vector2.ZERO
## "playing" or "menu". The menu states freeze the simulation instead of pausing
## the tree, so timers, audio and the menus themselves keep running.
var game_state := STATE_PLAYING
var pending_action := ""
## The ten explorable regions: one loaded at a time, everything else preserved.
var regions: RefCounted
var region_menu: Control
var _region_return := "gate"
var _suppress_region_closed := false
## What the context button does right now: "capture", "travel" or nothing.
var interact_mode := ""
var settings_opened_from_main := false
var _hunt_abandoned := false
var _suppress_settings_closed := false

# Automated testing hook: pass `--seed=<int>` as a user argument (after `--`),
# or export ATHAR_SEED, to force one reproducible world layout. Without either,
# the engine's normal random seed applies and gameplay is unchanged.
const TEST_SEED_ARG := "--seed="
var test_seed_active := false

const STATE_PLAYING := "playing"
const STATE_MENU := "menu"


## Read-only view of the deer's behaviour state, kept for simple access.
var deer_state: String:
	get:
		return deer_ai.state if deer_ai != null else DeerAI.GRAZING

## Read-only view of the current hunt's capture status.
var captured: bool:
	get:
		return hunt_session != null and hunt_session.is_captured


func _ready() -> void:
	_apply_test_seed()
	_setup_input()
	# Settings and language load before anything builds a label, so the first frame
	# is already in the player's language rather than flashing English.
	_load_settings()
	_build_environment()
	_build_world()
	_build_hunter()
	_build_deer()
	_build_camera()
	_build_living_world()
	_build_hud()
	_build_menus()
	_build_audio()
	_update_region_hud()
	deer_ai.state_changed.connect(_on_deer_state_changed)
	hunt_session.deer_captured.connect(_on_deer_captured)
	_update_status("hud.initial_status")
	_apply_graphics(audio_settings.quality)
	_apply_safe_area()
	# Desktop and Android players start on the title screen. Headless runs (the
	# automated suites and the screenshot tools) start straight in the hunt, which
	# is exactly how they behaved before this phase.
	if DisplayServer.get_name() != "headless":
		open_main_menu()
	# Printed when a test seed is active, or in headless runs, so the automated
	# tests can compare layouts. Desktop play stays silent.
	if test_seed_active or DisplayServer.get_name() == "headless":
		print("ATHAR_TEST_WORLD_CHECKSUM=", _world_checksum())


func _setup_input() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		if not InputMap.has_action(action): InputMap.add_action(action)

func _build_environment() -> void:
	environment_info = WildsEnvironment.build(self)

func _build_world() -> void:
	# The region manager owns everything that changes when the player travels; the
	# hunter, deer, camera and audio are built on top of it and never rebuilt.
	regions = RegionManager.new()
	regions.setup(self, environment_info, _seed_value if test_seed_active else -1)
	var result: Dictionary = regions.load_region(RegionManager.DEFAULT_REGION)
	if not result.get("ok", false):
		push_error("ATHAR: the default region failed to load: %s" % regions.last_error)
		return
	_adopt_region(result["info"])


## Points the scene's public references at the region that is now loaded, so the
## tests and the tools keep reading `ground_info` / `forest_info` as before.
func _adopt_region(info: Dictionary) -> void:
	ground_info = info["ground_info"]
	forest_info = info["forest_info"]
	environment_info["foliage_material"] = forest_info.get("material", null)


# --------------------------------------------------------------- the hunter ---
func _build_hunter() -> void:
	hunter = CharacterBody3D.new()
	hunter.name = "Hunter"
	hunter.position = Vector3(0, 0.1, 7)
	add_child(hunter)
	hunter_rig = HunterRig.new()
	hunter_rig.name = "HunterRig"
	hunter.add_child(hunter_rig)
	var collider := CollisionShape3D.new()
	collider.name = "HunterCollider"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.40
	shape.height = 1.80
	collider.shape = shape
	collider.position.y = 0.90
	hunter.add_child(collider)

# ---------------------------------------------------------------- the deer ---
func _build_deer() -> void:
	deer = CharacterBody3D.new()
	deer.name = "WildDeer"
	deer.position = Vector3(4.5, 0.1, -5.0)
	add_child(deer)
	deer_rig = DeerRig.new()
	deer_rig.name = "DeerRig"
	deer.add_child(deer_rig)
	deer_collider = CollisionShape3D.new()
	deer_collider.name = "DeerCollider"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 1.55
	deer_collider.shape = shape
	deer_collider.position.y = 0.78
	deer.add_child(deer_collider)
	hunt_session = HuntSession.new()
	# A supplied test seed also drives the deer's personality and wander, so a
	# seeded hunt replays exactly; normal play stays random.
	deer_ai = DeerAI.new(_active_seed())
	# The AI is pure logic; these two probes are how it asks the physics world
	# whether a trunk blocks its line of sight or its next step.
	deer_ai.set_navigation_probe(_deer_path_blocked)
	_apply_region_habitat()

func _active_seed() -> int:
	return int(_seed_value) if test_seed_active else -1

func _build_camera() -> void:
	# Presentation only: the rig smooths its own motion and pulls in when a tree
	# or the ground gets between it and the hunter.
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.ignore_bodies([hunter.get_rid(), deer.get_rid()])
	camera_rig.snap_to(hunter.global_position, hunter.rotation.y)
	camera = camera_rig.camera

## Time, weather, wind and rain. Built after the world so it can drive the trees,
## the ground and the lights that already exist.
func _build_living_world() -> void:
	living_world = LivingWorld.new()
	living_world.setup(environment_info, ground_info, _active_seed())
	# The region tint is a modifier over the clock, so it can only be installed
	# once the clock exists.
	if regions != null:
		regions.attach_living_world(living_world)
	_apply_wildlife_environment()


## Pushes the current environment's sense multipliers into the deer. Called on
## setup and whenever the phase or the weather label changes.
func _apply_wildlife_environment() -> void:
	if living_world == null or deer_ai == null:
		return
	_sync_audio_environment()
	var senses: Dictionary = living_world.wildlife_modifiers()
	deer_ai.set_environment_modifiers(float(senses["vision"]), float(senses["hearing"]), float(senses["memory"]))


## Loads the persisted preferences and switches the UI language before anything
## is built, so the first frame is already correct.
func _load_settings() -> void:
	audio_settings = GameSettings.new()
	audio_settings.load_settings()
	Localization.ensure_installed()
	Localization.set_language(audio_settings.language)


## The HUD is its own scene with its own layout code (scripts/ui/hud.gd). main.gd
## keeps the old public references — hunt_button, status_label, info_label,
## deer_marker — pointing at the new controls, so the Phase 3 tests and the
## screenshot tools keep working against a completely rebuilt interface.
func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HudLayer"
	hud_layer.layer = 5
	add_child(hud_layer)
	hud = HUD_SCENE.instantiate()
	hud_layer.add_child(hud)
	hud.setup(audio_settings)
	hud.action_pressed.connect(_on_hunt_pressed)
	hud.interact_pressed.connect(_on_interact_pressed)
	hud.pause_pressed.connect(open_pause)
	hud.move_changed.connect(_on_stick_moved)
	hud_root = hud
	status_label = hud.status_label
	info_label = hud.info_label
	hunt_button = hud.action_button
	deer_marker = hud.marker
	hud.layout_for(get_viewport().get_visible_rect().size)


## Title, pause and settings screens plus the confirmation prompt. They live on a
## layer above the HUD, are built once and are only shown or hidden afterwards.
func _build_menus() -> void:
	menu_layer = CanvasLayer.new()
	menu_layer.name = "MenuLayer"
	menu_layer.layer = 10
	add_child(menu_layer)

	main_menu = MAIN_MENU_SCENE.instantiate()
	menu_layer.add_child(main_menu)
	pause_menu = PAUSE_MENU_SCENE.instantiate()
	menu_layer.add_child(pause_menu)
	settings_menu = SETTINGS_MENU_SCENE.instantiate()
	menu_layer.add_child(settings_menu)
	settings_menu.setup(audio_settings)
	confirm_prompt = CONFIRM_SCENE.instantiate()
	menu_layer.add_child(confirm_prompt)
	region_menu = REGION_MENU_SCENE.instantiate()
	menu_layer.add_child(region_menu)

	main_menu.begin_pressed.connect(start_game)
	main_menu.settings_pressed.connect(func() -> void: open_settings(true))
	main_menu.regions_pressed.connect(func() -> void: open_region_menu("main"))
	main_menu.quit_pressed.connect(func() -> void: get_tree().quit())
	pause_menu.resume_pressed.connect(resume_game)
	pause_menu.settings_pressed.connect(func() -> void: open_settings(false))
	pause_menu.restart_pressed.connect(request_restart)
	pause_menu.menu_pressed.connect(request_return_to_menu)
	pause_menu.regions_pressed.connect(func() -> void: open_region_menu("pause"))
	region_menu.travel_requested.connect(_on_region_chosen)
	region_menu.closed.connect(_on_region_menu_closed)
	settings_menu.closed.connect(_on_settings_closed)
	settings_menu.language_changed.connect(_on_language_changed)
	settings_menu.quality_changed.connect(_apply_graphics)
	settings_menu.sensitivity_changed.connect(_on_sensitivity_changed)
	settings_menu.reset_requested.connect(_on_settings_reset)
	confirm_prompt.confirmed.connect(_on_confirmed)

## Sound. Built after the HUD so the volume panel can live in it, and after the
## deer exists so its voice can be attached to it in 3D.
func _build_audio() -> void:
	audio = AudioDirector.new()
	audio.name = "AudioDirector"
	add_child(audio)
	audio.setup(audio_settings)
	audio.attach_deer(deer)
	# The Phase 3.4 volume panel now lives inside the settings screen as a folded
	# section; the reference is kept so the audio suite still finds it.
	audio_panel = settings_menu.audio_section
	_sync_audio_environment()


## Hands the current hour and weather to the audio beds. Called on setup and
## whenever the phase or weather changes, not every frame.
func _sync_audio_environment() -> void:
	if audio == null or living_world == null:
		return
	var day: Dictionary = living_world.day.sample()
	var weather: Dictionary = living_world.weather.sample()
	audio.set_environment(float(day["night"]), float(weather["rain"]), float(weather["wind"]))



# ---------------------------------------------------------------- gameplay ---
func _physics_process(delta: float) -> void:
	if hunter == null or deer == null: return
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"): dir.z -= 1
	if Input.is_action_pressed("move_back"): dir.z += 1
	if Input.is_action_pressed("move_left"): dir.x -= 1
	if Input.is_action_pressed("move_right"): dir.x += 1
	# Touch pad: screen up is -y and forward is -z, so the axes map straight
	# across. Keys and the stick add together without breaking the old path.
	dir.x += joystick_vector.x
	dir.z += joystick_vector.y
	if dir.length() > 0.001:
		dir = dir.normalized()
		hunter.velocity.x = dir.x * HUNTER_SPEED
		hunter.velocity.z = dir.z * HUNTER_SPEED
		hunter.rotation.y = lerp_angle(hunter.rotation.y, atan2(-dir.x, -dir.z), delta * HUNTER_TURN_RATE)
		stamina = maxf(0, stamina - delta * 2.5)
	else:
		hunter.velocity.x = move_toward(hunter.velocity.x, 0, HUNTER_BRAKE * delta)
		hunter.velocity.z = move_toward(hunter.velocity.z, 0, HUNTER_BRAKE * delta)
		stamina = minf(100, stamina + delta * 5.0)
	hunter.velocity.y -= GRAVITY * delta
	hunter.move_and_slide()
	hunter.global_position.x = clampf(hunter.global_position.x, -HUNTER_LIMIT, HUNTER_LIMIT)
	hunter.global_position.z = clampf(hunter.global_position.z, -HUNTER_LIMIT, HUNTER_LIMIT)
	hunter_rig.animate(delta, Vector2(hunter.velocity.x, hunter.velocity.z).length())
	if living_world != null:
		living_world.update(delta, hunter.global_position)
		if living_world.consume_change():
			_apply_wildlife_environment()
	_update_deer(delta)
	_check_capture()
	if audio != null:
		audio.update(delta, hunter.global_position, Vector2(hunter.velocity.x, hunter.velocity.z).length(), deer.global_position, deer_speed)
	camera_rig.update_camera(delta, hunter.global_position, hunter.rotation.y)
	if deer_marker != null:
		deer_marker.update_marker(camera, deer.global_position, deer.visible and not hunt_session.is_captured)
	_update_hud()

## True when a trunk sits on the straight line from `from` to `to`. Only tree
## trunks (layer 2) and the ground (layer 1) count; the deer itself is excluded.
func _deer_sight_blocked(from: Vector3, to: Vector3) -> bool:
	return _deer_ray_blocked(from + Vector3.UP * 1.10, to + Vector3.UP * 1.10)

## True when the deer's next step would run into a trunk.
func _deer_path_blocked(from: Vector3, to: Vector3) -> bool:
	return _deer_ray_blocked(from + Vector3.UP * 0.90, to + Vector3.UP * 0.90)

func _deer_ray_blocked(from: Vector3, to: Vector3) -> bool:
	if deer == null or not is_inside_tree() or get_world_3d() == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to, 3, [deer.get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _update_deer(delta: float) -> void:
	if hunt_session.is_captured:
		return
	var desired: Vector3 = deer_ai.update(delta, deer.global_position, hunter.global_position, _deer_sight_blocked)
	deer.velocity.x = desired.x
	deer.velocity.z = desired.z
	var planar := Vector2(desired.x, desired.z).length()
	deer_speed = planar
	if planar > 0.05:
		deer.rotation.y = lerp_angle(deer.rotation.y, atan2(-desired.x, -desired.z), delta * 6.0)
	deer.velocity.y -= GRAVITY * delta
	deer.move_and_slide()
	deer.global_position.x = clampf(deer.global_position.x, -DEER_LIMIT, DEER_LIMIT)
	deer.global_position.z = clampf(deer.global_position.z, -DEER_LIMIT, DEER_LIMIT)
	deer_rig.set_state(deer_ai.state)
	deer_rig.animate(delta, planar)

## Capture happens on contact: reaching the deer ends the hunt. The HUNT button
## still works too, so the original control keeps doing something sensible.
func _check_capture() -> void:
	if hunt_session == null or hunt_session.is_captured:
		return
	var distance := hunter.global_position.distance_to(deer.global_position)
	hunt_session.try_capture(distance)

func _on_deer_captured() -> void:
	if audio != null:
		audio.play_capture()
	deer_ai.capture()
	deer_rig.set_state(DeerAI.CAPTURED)
	deer.velocity = Vector3.ZERO
	_set_deer_collision(false)
	deer.visible = false
	if hud != null:
		hud.set_action_key("hud.action.new_hunt")
		hud.set_interact_key("")
		hud.toast("toast.captured")
	_update_status("status.captured")

func _on_deer_state_changed(previous: String, current: String) -> void:
	match current:
		DeerAI.ALERTED:
			_update_status("status.alerted")
			if audio != null:
				audio.play_deer_alert()
		DeerAI.INVESTIGATING:
			_update_status("status.investigating")
		DeerAI.FLEEING:
			_update_status("status.fleeing")
			if audio != null:
				audio.play_deer_flee()
		DeerAI.ESCAPING:
			_update_status("status.escaping")
		DeerAI.RETURNING:
			_update_status("status.returning")
		DeerAI.GRAZING:
			if previous in [DeerAI.ESCAPING, DeerAI.RETURNING]:
				_update_status("status.escaped")
		DeerAI.RESTING:
			if previous == DeerAI.GRAZING:
				_update_status("status.resting")

## Capture disables the deer's collision so it cannot be pushed, collided with,
## or captured again; a new hunt re-enables it.
func _set_deer_collision(enabled: bool) -> void:
	if deer_collider == null:
		return
	deer_collider.set_deferred("disabled", not enabled)
	deer.set_deferred("collision_layer", 1 if enabled else 0)
	deer.set_deferred("collision_mask", 1 if enabled else 0)

func _on_hunt_pressed() -> void:
	if audio != null:
		audio.play_ui_tap()
	if hunt_session.is_captured:
		_start_new_hunt()
		return
	var distance := hunter.global_position.distance_to(deer.global_position)
	if hunt_session.distance_in_reach(distance):
		hunt_session.try_capture(distance)
	elif hud != null:
		# The status line carries the story; the toast answers the touch itself, so
		# a refused press still feels like it did something.
		hud.toast("toast.too_far", int(distance))

## GRAZING -> ALERTED -> FLEEING -> CHASE -> CAPTURED -> NEW HUNT.
func _start_new_hunt() -> void:
	if not hunt_session.begin_new_hunt():
		return
	deer.global_position = _pick_deer_spot()
	deer.velocity = Vector3.ZERO
	deer.rotation.y = randf() * TAU
	deer.visible = true
	_set_deer_collision(true)
	deer_ai.reset()
	deer_rig.set_state(DeerAI.GRAZING)
	if hud != null:
		hud.set_action_key("hud.action.hunt")
		hud.toast("toast.new_hunt")
	_update_status("status.new_hunt")

func _pick_deer_spot() -> Vector3:
	# Regions may ask for a different habitat range, but never a closer one than
	# the Phase 3.2 fairness floor: a deer must not spawn in the player's lap.
	var habitat := _region_habitat()
	var min_distance := maxf(float(habitat.get("spawn_min", NEW_HUNT_MIN_DISTANCE)), NEW_HUNT_MIN_DISTANCE)
	var max_distance := maxf(float(habitat.get("spawn_max", NEW_HUNT_MAX_DISTANCE)), min_distance)
	for attempt in range(20):
		var angle := randf() * TAU
		var radius := randf_range(min_distance, max_distance)
		var spot := hunter.global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if absf(spot.x) <= 38.0 and absf(spot.z) <= 38.0:
			return Vector3(spot.x, 0.1, spot.z)
	return hunter.global_position + Vector3(0, 0.1, -NEW_HUNT_MIN_DISTANCE)

## `key` is a localization key, never a sentence, so the message survives a
## language change and the same state can be announced in either language.
func _update_status(key: String) -> void:
	if hud != null:
		hud.set_status_key(key)
	elif status_label != null:
		status_label.text = key

# Seeds the global RNG only when a test seed was supplied. See TESTING.md.
var _seed_value := 0

func _apply_test_seed() -> void:
	var value = _read_test_seed()
	if value == null:
		return
	seed(value)
	_seed_value = int(value)
	test_seed_active = true
	print("ATHAR_TEST_SEED=", value)

func _read_test_seed():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(TEST_SEED_ARG):
			var raw := arg.substr(TEST_SEED_ARG.length()).strip_edges()
			if raw.is_valid_int():
				return int(raw)
	var from_env := OS.get_environment("ATHAR_SEED").strip_edges()
	if from_env.is_valid_int():
		return int(from_env)
	return null

## Stable fingerprint of the generated world, used to prove a seed reproduces it.
## Trees, stones and grass are MultiMesh batches now, so the instance transforms
## have to be part of the fingerprint, not just standalone mesh nodes.
func _world_checksum() -> String:
	var parts := PackedStringArray()
	for child in get_children():
		if child is MultiMeshInstance3D:
			var multimesh: MultiMesh = child.multimesh
			parts.append("mm:%d:%d" % [child.get_index(), multimesh.instance_count])
			for i in range(multimesh.instance_count):
				var origin: Vector3 = multimesh.get_instance_transform(i).origin
				parts.append("%.3f,%.3f,%.3f" % [origin.x, origin.y, origin.z])
		elif child is MeshInstance3D:
			parts.append("%.4f,%.4f,%.4f" % [child.position.x, child.position.y, child.position.z])
	return ",".join(parts).sha256_text()


# ------------------------------------------------------------------- hud -----
## Vitals, the time/weather/quarry line and the context buttons, refreshed every
## physics step. The HUD ignores calls that do not change anything, so an idle
## screen costs comparisons rather than layout work.
func _update_hud() -> void:
	if hud == null or living_world == null:
		return
	var condition: float = clampf(deer_ai.stamina, 0.0, 1.0)
	hud.set_vitals(clampf(stamina / 100.0, 0.0, 1.0), condition, _alert_level())
	hud.set_info(
		living_world.day.clock_text(),
		"hud.phase." + String(living_world.day.phase()),
		"hud.weather." + String(living_world.weather.label()).to_lower(),
		"hud.deer." + deer_ai.activity_text())
	_update_context()


## How aware the deer is, 0..1, derived from its behaviour state rather than a
## separate hidden number — the bar shows what the animal is actually doing.
func _alert_level() -> float:
	match deer_state:
		DeerAI.FLEEING:
			return 1.0
		DeerAI.ALERTED:
			return 0.85
		DeerAI.ESCAPING:
			return 0.7
		DeerAI.INVESTIGATING:
			return 0.6
		DeerAI.OBSERVING:
			return 0.4
		DeerAI.RESTING:
			return 0.2
		DeerAI.GRAZING:
			return 0.15
	return 0.0


## The big button tracks the hunt, and the context button only appears when the
## deer is close enough to touch — a button that cannot do anything is hidden.
func _update_context() -> void:
	if hud == null or hunt_session == null:
		return
	if captured:
		hud.set_action_key("hud.action.new_hunt")
		hud.set_interact_key("regions.travel" if _near_gate() else "")
		interact_mode = "travel" if _near_gate() else ""
		return
	hud.set_action_key("hud.action.hunt")
	var distance := hunter.global_position.distance_to(deer.global_position)
	if hunt_session.distance_in_reach(distance):
		interact_mode = "capture"
		hud.set_interact_key("hud.capture")
	elif _near_gate():
		interact_mode = "travel"
		hud.set_interact_key("regions.travel")
	else:
		interact_mode = ""
		hud.set_interact_key("")


func _on_stick_moved(value: Vector2) -> void:
	joystick_vector = value


## The context button takes the deer when it is within reach, and opens the
## region screen when the player is standing at a gate.
func _on_interact_pressed() -> void:
	if interact_mode == "travel":
		open_region_menu("gate")
		return
	if deer == null or hunt_session == null:
		return
	var distance := hunter.global_position.distance_to(deer.global_position)
	if hunt_session.distance_in_reach(distance):
		hunt_session.try_capture(distance)
	elif hud != null:
		hud.toast("toast.too_far", int(distance))


# ----------------------------------------------------------------- regions ---
## The loaded region's definition, or an empty dictionary before the world exists.
func current_region() -> Dictionary:
	if regions == null or regions.region_info.is_empty():
		return {}
	return regions.region_info["region"]


func current_region_id() -> String:
	return regions.active_id if regions != null else ""


func _region_habitat() -> Dictionary:
	return current_region().get("habitat", {})


## Applies the loaded region's wildlife habitat. Only the temperament changes: the
## senses, speeds and capture distance are the tuned Phase 3.2 values, so travel
## never alters hunting balance.
func _apply_region_habitat() -> void:
	if deer_ai == null:
		return
	var archetype := String(_region_habitat().get("archetype", ""))
	if not archetype.is_empty():
		deer_ai.set_habitat(archetype)
	if living_world != null:
		_apply_wildlife_environment()


## Re-places the deer for the region that just loaded. A secured quarry stays
## secured: its capture is player state too, and travel must not erase it.
func _respawn_quarry() -> void:
	if deer == null or deer_ai == null or hunt_session == null:
		return
	if hunt_session.is_captured:
		return
	deer.global_position = _pick_deer_spot()
	deer.velocity = Vector3.ZERO
	deer.rotation.y = randf() * TAU
	deer.visible = true
	_set_deer_collision(true)
	deer_ai.reset()
	deer_rig.set_state(DeerAI.GRAZING)


## Moves the player to another region. Everything that belongs to the player —
## breath, the hunt and its capture count, settings, language, audio — survives;
## only the ground, the woodland, the landmark and the quarry are replaced.
func travel_to(id: String) -> bool:
	if regions == null or hunter == null or not regions.can_enter(id):
		return false
	if id == regions.active_id:
		return false
	set_physics_process(false)
	if hud != null:
		hud.release_controls()
	var kept_stamina := stamina
	var result: Dictionary = regions.load_region(id)
	if not result.get("ok", false):
		set_physics_process(true)
		if hud != null:
			hud.toast("toast.region_missing")
		return false
	_adopt_region(result["info"])
	hunter.global_position = regions.entry_point()
	hunter.velocity = Vector3.ZERO
	stamina = kept_stamina
	_apply_region_habitat()
	_respawn_quarry()
	if camera_rig != null:
		camera_rig.snap_to(hunter.global_position, hunter.rotation.y)
	_sync_audio_environment()
	_update_region_hud()
	if audio != null:
		audio.play_ui_tap()
	if hud != null:
		hud.toast("toast.region")
	_update_status("status.region_entered")
	set_physics_process(true)
	return true


func _update_region_hud() -> void:
	if hud == null or regions == null:
		return
	var summary: Dictionary = regions.current_summary()
	if summary.is_empty():
		return
	hud.set_region(String(summary["name_key"]), int(summary["discovered"]), int(summary["total"]))


func _near_gate() -> bool:
	if regions == null or hunter == null or regions.gate_position == Vector3.ZERO:
		return false
	return hunter.global_position.distance_to(regions.gate_position) <= GATE_RADIUS


func open_region_menu(from := "gate") -> void:
	if region_menu == null or regions == null:
		return
	_region_return = from
	game_state = STATE_MENU
	set_physics_process(false)
	if hud != null:
		hud.release_controls()
	main_menu.close()
	pause_menu.close()
	settings_menu.close()
	confirm_prompt.dismiss()
	region_menu.open(regions.region_listing())
	if audio != null:
		audio.play_ui_tap()


func _on_region_chosen(id: String) -> void:
	var travelled := travel_to(id)
	_suppress_region_closed = true
	region_menu.close()
	_suppress_region_closed = false
	game_state = STATE_PLAYING
	set_physics_process(true)
	if travelled:
		_update_region_hud()
		return
	# Same region, or a refused transition: put the player back where they were.
	if _region_return == "pause":
		game_state = STATE_MENU
		set_physics_process(false)
		pause_menu.open()
	elif _region_return == "main":
		game_state = STATE_MENU
		set_physics_process(false)
		main_menu.open()
	else:
		_update_status("hud.initial_status")


func _on_region_menu_closed() -> void:
	if _suppress_region_closed:
		return
	region_menu.close()
	if _region_return == "pause":
		pause_menu.open()
		game_state = STATE_MENU
		set_physics_process(false)
	elif _region_return == "main":
		main_menu.open()
		game_state = STATE_MENU
		set_physics_process(false)
	else:
		game_state = STATE_PLAYING
		set_physics_process(true)


# ------------------------------------------------------------------ menus ----
func open_main_menu() -> void:
	if main_menu == null:
		return
	pause_menu.close()
	settings_menu.close()
	confirm_prompt.dismiss()
	main_menu.open()
	game_state = STATE_MENU
	set_physics_process(false)
	if hud != null:
		hud.release_controls()


func start_game() -> void:
	if audio != null:
		audio.play_ui_tap()
	main_menu.close()
	settings_menu.close()
	confirm_prompt.dismiss()
	game_state = STATE_PLAYING
	set_physics_process(true)
	if _hunt_abandoned:
		_hunt_abandoned = false
		_reset_hunt_state()


func open_pause() -> void:
	if game_state == STATE_MENU or pause_menu == null:
		return
	game_state = STATE_MENU
	set_physics_process(false)
	if hud != null:
		hud.release_controls()
	if audio != null:
		audio.play_ui_tap()
	pause_menu.open()


func resume_game() -> void:
	pause_menu.close()
	# Closing the settings screen normally re-opens the pause menu; resuming is the
	# one case where that must not happen.
	_suppress_settings_closed = true
	settings_menu.close()
	_suppress_settings_closed = false
	confirm_prompt.dismiss()
	game_state = STATE_PLAYING
	set_physics_process(true)


func open_settings(from_main: bool) -> void:
	settings_opened_from_main = from_main
	if from_main:
		main_menu.close()
	else:
		pause_menu.close()
	settings_menu.open()


func _on_settings_closed() -> void:
	if _suppress_settings_closed:
		return
	if settings_opened_from_main:
		settings_opened_from_main = false
		main_menu.open()
	else:
		pause_menu.open()
	if audio_settings != null:
		audio_settings.save()


## Restart and "main menu" both go through the prompt: a thumb slips on a phone,
## and throwing away a hunt on a mis-touch is not acceptable.
func request_restart() -> void:
	pending_action = "restart"
	confirm_prompt.ask("confirm.restart.title", "confirm.restart.body")


func request_return_to_menu() -> void:
	pending_action = "menu"
	confirm_prompt.ask("confirm.return.title", "confirm.return.body")


func _on_confirmed() -> void:
	var action := pending_action
	pending_action = ""
	match action:
		"restart":
			pause_menu.close()
			game_state = STATE_PLAYING
			set_physics_process(true)
			_reset_hunt_state()
		"menu":
			_hunt_abandoned = true
			open_main_menu()


## Drops the deer somewhere fair, restores its collision and clears the chase.
## Works whether the previous hunt ended in a capture or was simply restarted.
func _reset_hunt_state() -> void:
	if deer == null or deer_ai == null:
		return
	if hunt_session.is_captured:
		_start_new_hunt()
		stamina = 100.0
		return
	deer.global_position = _pick_deer_spot()
	deer.velocity = Vector3.ZERO
	deer.rotation.y = randf() * TAU
	deer.visible = true
	_set_deer_collision(true)
	deer_ai.reset()
	deer_rig.set_state(DeerAI.GRAZING)
	stamina = 100.0
	if hud != null:
		hud.set_action_key("hud.action.hunt")
		hud.set_interact_key("")
	_update_status("status.new_hunt")


# --------------------------------------------------------------- settings ----
func _on_language_changed(code: String) -> void:
	Localization.set_language(code)
	_retranslate_ui()


func _retranslate_ui() -> void:
	for ui in [hud, main_menu, pause_menu, settings_menu, confirm_prompt, region_menu]:
		if ui != null:
			ui.retranslate()
	_update_region_hud()


func _apply_graphics(level: String) -> void:
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	GraphicsProfile.apply(level, get_viewport(), sun)


func _on_sensitivity_changed(value: float) -> void:
	if audio_settings != null:
		audio_settings.set_sensitivity(value)
	if hud != null:
		hud.set_sensitivity(value)


func _on_settings_reset() -> void:
	audio_settings.apply()
	Localization.set_language(audio_settings.language)
	_apply_graphics(audio_settings.quality)
	if hud != null:
		hud.set_sensitivity(audio_settings.sensitivity)
		hud.toast("toast.saved")
	_retranslate_ui()


## Android reports a safe area for notches and rounded corners; the HUD keeps its
## controls inside it. On a desktop or in a headless run there is no inset.
func _apply_safe_area() -> void:
	if hud == null:
		return
	var safe := DisplayServer.get_display_safe_area()
	var window := DisplayServer.window_get_size()
	if safe.size.x <= 0 or safe.size.y <= 0 or window.x <= 0 or window.y <= 0:
		hud.set_safe_insets(0.0, 0.0, 0.0, 0.0)
		return
	hud.apply_safe_area(safe, window, get_viewport().get_visible_rect().size)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_apply_safe_area()


func _exit_tree() -> void:
	# The UI kit caches the theme, styles and fonts in statics for the whole run;
	# drop them on shutdown so nothing is reported as leaked at exit.
	UiKit.release_cache()

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
const DeerMarker := preload("res://scripts/ui/deer_marker.gd")

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
## Summary dictionaries from the visual builders, used by the visual tests.
var forest_info := {}
var ground_info := {}
var environment_info := {}
var status_label: Label
var info_label: Label
var move_vector := Vector2.ZERO
var stamina := 100.0
var hunt_button: Button

# Automated testing hook: pass `--seed=<int>` as a user argument (after `--`),
# or export ATHAR_SEED, to force one reproducible world layout. Without either,
# the engine's normal random seed applies and gameplay is unchanged.
const TEST_SEED_ARG := "--seed="
var test_seed_active := false


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
	_build_environment()
	_build_world()
	_build_hunter()
	_build_deer()
	_build_camera()
	_build_hud()
	deer_ai.state_changed.connect(_on_deer_state_changed)
	hunt_session.deer_captured.connect(_on_deer_captured)
	_update_status("Find the deer. Move quietly through the forest.")
	# Printed when a test seed is active, or in headless runs, so the automated
	# tests can compare layouts. Desktop play stays silent.
	if test_seed_active or DisplayServer.get_name() == "headless":
		print("ATHAR_TEST_WORLD_CHECKSUM=", _world_checksum())


func _setup_input() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		if not InputMap.has_action(action): InputMap.add_action(action)

func _mat(color: Color, roughness := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

func _mesh_node(parent: Node, mesh: Mesh, material: Material, pos: Vector3, scale := Vector3.ONE) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = material
	n.position = pos
	n.scale = scale
	parent.add_child(n)
	return n

func _build_environment() -> void:
	environment_info = WildsEnvironment.build(self)

func _build_world() -> void:
	# One generator for the whole world, seeded from the global RNG: a test seed
	# still reproduces the forest, stones and grass exactly.
	var world_rng := RandomNumberGenerator.new()
	world_rng.seed = randi()
	ground_info = WildsGround.build(self, world_rng)
	forest_info = Forest.build(self, world_rng)
	# A small ruined stone arch gives the clearing a landmark.
	_create_ruin(Vector3(-10, 0, -15))

func _create_ruin(p: Vector3) -> void:
	var stone := _mat(Color(0.175, 0.185, 0.165))
	for x in [-2.2, 2.2]:
		var pillar := BoxMesh.new()
		pillar.size = Vector3(0.8, 4.2, 0.9)
		_mesh_node(self, pillar, stone, p + Vector3(x, 2.1, 0))
	var lintel := BoxMesh.new()
	lintel.size = Vector3(5.2, 0.8, 1.0)
	_mesh_node(self, lintel, stone, p + Vector3(0, 4.2, 0))

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

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var title := Label.new()
	title.text = "ATHAR  |  WILDLANDS"
	title.position = Vector2(26, 18)
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color(0.91, 0.78, 0.48))
	root.add_child(title)
	status_label = Label.new()
	status_label.position = Vector2(28, 58)
	status_label.add_theme_font_size_override("font_size", 17)
	status_label.add_theme_color_override("font_color", Color(0.92, 0.93, 0.84))
	root.add_child(status_label)
	info_label = Label.new()
	info_label.text = "STAMINA 100%   •   FOREST REGION"
	info_label.position = Vector2(28, 88)
	info_label.add_theme_font_size_override("font_size", 14)
	info_label.add_theme_color_override("font_color", Color(0.64, 0.82, 0.72))
	root.add_child(info_label)
	_add_hold_button(root, "▲", Vector2(112, -184), "move_forward")
	_add_hold_button(root, "▼", Vector2(112, -64), "move_back")
	_add_hold_button(root, "◀", Vector2(52, -124), "move_left")
	_add_hold_button(root, "▶", Vector2(172, -124), "move_right")
	# Edge-of-screen cue for a deer that has left the frame. Added after the
	# labels so it never covers the HUD text, and ignored by the mouse.
	deer_marker = DeerMarker.new()
	deer_marker.name = "DeerMarker"
	deer_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(deer_marker)
	hunt_button = Button.new()
	hunt_button.text = "HUNT / TRACK"
	hunt_button.position = Vector2(-210, -105)
	hunt_button.size = Vector2(180, 66)
	hunt_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hunt_button.add_theme_font_size_override("font_size", 19)
	hunt_button.add_theme_color_override("font_color", Color(0.98, 0.88, 0.63))
	hunt_button.add_theme_stylebox_override("normal", _button_style(Color(0.20, 0.27, 0.19, 0.94)))
	hunt_button.add_theme_stylebox_override("pressed", _button_style(Color(0.42, 0.30, 0.13, 0.98)))
	hunt_button.pressed.connect(_on_hunt_pressed)
	root.add_child(hunt_button)
	var hint := Label.new()
	hint.text = "Move with the left controls • Approach slowly • Run it down when it bolts"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(24, -32)
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.86, 0.86, 0.76))
	root.add_child(hint)

func _button_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = Color(0.68, 0.59, 0.35, 0.8)
	s.set_border_width_all(2)
	s.set_corner_radius_all(18)
	return s

func _add_hold_button(parent: Control, caption: String, offset: Vector2, action: String) -> void:
	var b := Button.new()
	b.text = caption
	b.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	b.position = offset
	b.size = Vector2(58, 58)
	b.add_theme_font_size_override("font_size", 25)
	b.add_theme_color_override("font_color", Color(0.96, 0.91, 0.75))
	b.add_theme_stylebox_override("normal", _button_style(Color(0.12, 0.19, 0.16, 0.88)))
	b.add_theme_stylebox_override("pressed", _button_style(Color(0.35, 0.34, 0.20, 0.98)))
	b.button_down.connect(func(): Input.action_press(action))
	b.button_up.connect(func(): Input.action_release(action))
	parent.add_child(b)

# ---------------------------------------------------------------- gameplay ---
func _physics_process(delta: float) -> void:
	if hunter == null or deer == null: return
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"): dir.z -= 1
	if Input.is_action_pressed("move_back"): dir.z += 1
	if Input.is_action_pressed("move_left"): dir.x -= 1
	if Input.is_action_pressed("move_right"): dir.x += 1
	if dir.length() > 0:
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
	_update_deer(delta)
	_check_capture()
	camera_rig.update_camera(delta, hunter.global_position, hunter.rotation.y)
	if deer_marker != null:
		deer_marker.update_marker(camera, deer.global_position, deer.visible and not hunt_session.is_captured)
	info_label.text = "STAMINA %d%%   •   FOREST REGION   •   DEER %s" % [int(stamina), deer_ai.activity_text().to_upper()]

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
	deer_ai.capture()
	deer_rig.set_state(DeerAI.CAPTURED)
	deer.velocity = Vector3.ZERO
	_set_deer_collision(false)
	deer.visible = false
	hunt_button.text = "NEW HUNT"
	_update_status("Successful capture! The deer is secured. Press NEW HUNT to track another.")

func _on_deer_state_changed(previous: String, current: String) -> void:
	match current:
		DeerAI.ALERTED:
			_update_status("The deer lifts its head — it has noticed you. Hold still.")
		DeerAI.INVESTIGATING:
			_update_status("It is edging closer to look. Do not move yet.")
		DeerAI.FLEEING:
			_update_status("It bolted! Chase now — it will tire before you do.")
		DeerAI.ESCAPING:
			_update_status("The deer is tiring. Keep the pressure on and close the gap.")
		DeerAI.RETURNING:
			_update_status("It is drifting away, still wary. Let it settle.")
		DeerAI.GRAZING:
			if previous in [DeerAI.ESCAPING, DeerAI.RETURNING]:
				_update_status("The deer slipped away and settled down. Approach quietly again.")
		DeerAI.RESTING:
			if previous == DeerAI.GRAZING:
				_update_status("The deer has settled to rest. Move slowly.")

## Capture disables the deer's collision so it cannot be pushed, collided with,
## or captured again; a new hunt re-enables it.
func _set_deer_collision(enabled: bool) -> void:
	if deer_collider == null:
		return
	deer_collider.set_deferred("disabled", not enabled)
	deer.set_deferred("collision_layer", 1 if enabled else 0)
	deer.set_deferred("collision_mask", 1 if enabled else 0)

func _on_hunt_pressed() -> void:
	if hunt_session.is_captured:
		_start_new_hunt()
		return
	var distance := hunter.global_position.distance_to(deer.global_position)
	if hunt_session.distance_in_reach(distance):
		hunt_session.try_capture(distance)
	else:
		_update_status("Too far away (%dm). Close the distance — it tires before you do." % int(distance))

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
	hunt_button.text = "HUNT / TRACK"
	_update_status("A new deer has wandered into the clearing. Approach quietly.")

func _pick_deer_spot() -> Vector3:
	for attempt in range(20):
		var angle := randf() * TAU
		var radius := randf_range(NEW_HUNT_MIN_DISTANCE, NEW_HUNT_MAX_DISTANCE)
		var spot := hunter.global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if absf(spot.x) <= 38.0 and absf(spot.z) <= 38.0:
			return Vector3(spot.x, 0.1, spot.z)
	return hunter.global_position + Vector3(0, 0.1, -NEW_HUNT_MIN_DISTANCE)

func _update_status(message: String) -> void:
	if status_label:
		status_label.text = message

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

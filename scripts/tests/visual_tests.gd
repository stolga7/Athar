extends Node
## Headless tests for the Phase 3.1 visual layer: camera, forest, environment,
## ground and the deer cue.
##
## Run with:
##   godot --headless --path . res://scenes/tests/visual_tests.tscn
##
## Exits 0 only when every check passes. The camera tests use the real main
## scene and its real physics world, because the obstruction probe is a physics
## query: a fake world would not prove anything. The forest tests build the
## generator directly with a seeded RNG.
##
## These tests check configuration and measured behaviour. They cannot and do not
## claim that the result looks good: that needs rendered frames, which
## scripts/tools/capture_shots.gd produces on a machine with a display.

const MainScript := preload("res://scripts/main.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const CameraRig := preload("res://scripts/visuals/camera_rig.gd")
const Forest := preload("res://scripts/visuals/forest.gd")
const WildsEnvironment := preload("res://scripts/visuals/wilds_environment.gd")
const WildsGround := preload("res://scripts/visuals/wilds_ground.gd")

const DT := 1.0 / 60.0
const WATCHDOG_SECONDS := 90.0

var _checks := 0
var _failures := 0
var _main: Node3D
var _watchdog: Timer


func _ready() -> void:
	print("ATHAR visual tests")
	_watchdog = Timer.new()
	_watchdog.wait_time = WATCHDOG_SECONDS
	_watchdog.one_shot = true
	_watchdog.timeout.connect(_on_watchdog_timeout)
	add_child(_watchdog)
	_watchdog.start()

	await _test_camera_framing()
	await _test_camera_obstruction()
	await _test_camera_stability()
	_test_camera_clearance_under_canopy()
	_test_forest_structure()
	_test_forest_determinism()
	await _test_environment_and_ground()
	await _test_deer_marker()
	await _test_gameplay_preserved()
	_finish()


func _finish() -> void:
	_watchdog.stop()
	# Phase 3.4: the scene under test plays audio. Stop it, let the scene go (it
	# keeps walking, and a walking deer keeps making hoofbeats), then let the
	# mixer notice before quitting; an in-flight stream is reported as leaked.
	_silence_audio(get_tree().root)
	if _main != null:
		_main.free()
		_main = null
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


func _silence_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stop()
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stop()
	for child in node.get_children():
		_silence_audio(child)


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


func _load_main() -> void:
	if _main != null:
		_silence_audio(_main)
		# Give the mixer a few frames to release the stopped streams before the
		# players are freed with the scene.
		for _i in range(3):
			await get_tree().process_frame
		_main.queue_free()
		await get_tree().process_frame
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	for _i in range(3):
		await get_tree().physics_frame


# ------------------------------------------------------------------- camera ---
func _test_camera_framing() -> void:
	await _load_main()
	var rig = _main.camera_rig
	_check(rig != null and rig.camera != null, "scene builds a camera rig")
	_check(_main.camera == rig.camera and rig.camera.current, "the rig camera is the active camera")
	_check(absf(rig.camera.fov - CameraRig.FIELD_OF_VIEW) < 0.01, "camera uses the configured field of view", "%.0f deg" % rig.camera.fov)

	# Let the camera settle on the stationary hunter.
	for _i in range(30):
		await get_tree().physics_frame
	var hunter_position: Vector3 = _main.hunter.global_position
	var camera_position: Vector3 = rig.camera.global_position
	var to_camera := camera_position - hunter_position
	var flat := Vector2(to_camera.x, to_camera.z).length()

	_check(absf(rig.distance - CameraRig.DISTANCE) < 0.15, "camera holds its configured distance", "%.2f m" % rig.distance)
	_check(flat > 4.0 and flat < 7.5, "camera sits at a mobile third-person distance", "%.2f m behind" % flat)
	_check(camera_position.y > hunter_position.y + 1.6 and camera_position.y < hunter_position.y + 3.4, "camera is above the hunter's head", "%.2f m up" % (camera_position.y - hunter_position.y))

	# The hunter must be in the lower half of the frame, not filling it.
	await get_tree().process_frame
	var screen: Vector2 = rig.camera.unproject_position(hunter_position)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_check(screen.x > 0 and screen.x < viewport_size.x, "hunter is on screen horizontally", "x=%.0f" % screen.x)
	var height_fraction: float = clampf(2.0 * atan(1.9 * 0.5 / flat) / deg_to_rad(rig.camera.fov), 0.0, 1.0)
	_check(height_fraction > 0.20, "hunter reads at a third-person scale", "%.0f%% of the frame height" % (height_fraction * 100.0))

	# The camera looks over the right shoulder, so the hunter is not dead centre.
	var perp := Vector2(-to_camera.z, to_camera.x).normalized()
	var hunter_forward := Vector2(-sin(_main.hunter.rotation.y), -cos(_main.hunter.rotation.y))
	var shoulder: float = absf(perp.dot(hunter_forward)) * flat
	_check(shoulder > 0.3, "camera is offset to a shoulder", "%.2f m" % shoulder)


func _test_camera_obstruction() -> void:
	# Put a trunk-like pillar on the camera line, exactly the owner's complaint.
	var rig = _main.camera_rig
	var hunter_position: Vector3 = _main.hunter.global_position
	var camera_position: Vector3 = rig.camera.global_position
	var obstacle := StaticBody3D.new()
	obstacle.name = "TestTrunk"
	obstacle.collision_layer = Forest.COLLISION_LAYER
	obstacle.collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = 0.35
	shape.height = 6.0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	obstacle.add_child(collider)
	obstacle.position = hunter_position.lerp(camera_position, 0.45) + Vector3(0, 1.4, 0)
	_main.add_child(obstacle)

	for _i in range(20):
		await get_tree().physics_frame
	_check(rig.obstructed, "camera detects an obstruction between it and the hunter", "clear %.2f m" % rig.clear_distance)
	_check(rig.distance < 4.0, "camera pulls in when blocked", "%.2f m" % rig.distance)
	_check(rig.distance >= CameraRig.MIN_DISTANCE - 0.01, "camera never pulls in past its floor", "%.2f m" % rig.distance)
	var from_trunk: float = (rig.camera.global_position - obstacle.global_position).length()
	_check(from_trunk > 0.45, "camera does not sit inside the obstruction", "%.2f m clear" % from_trunk)
	_check(rig.camera.global_position.y > CameraRig.GROUND_CLEARANCE - 0.01, "camera stays above the ground", "y=%.2f" % rig.camera.global_position.y)

	obstacle.queue_free()
	for _i in range(150):
		await get_tree().physics_frame
	_check(not rig.obstructed, "camera reports clear once the obstruction is gone")
	_check(rig.distance > CameraRig.DISTANCE - 0.5, "camera drifts back out after an obstruction", "%.2f m" % rig.distance)


func _test_camera_stability() -> void:
	var rig = _main.camera_rig
	for _i in range(40):
		await get_tree().physics_frame
	var before: Vector3 = rig.camera.global_position
	for _i in range(30):
		await get_tree().physics_frame
	var drift: float = rig.camera.global_position.distance_to(before)
	_check(drift < 0.05, "camera does not jitter while the hunter stands still", "%.3f m over 30 frames" % drift)

	# A sudden teleport must not teleport the camera with it.
	_main.hunter.global_position += Vector3(3.0, 0, 0)
	await get_tree().physics_frame
	var step: float = rig.camera.global_position.distance_to(before)
	_check(step < 2.0, "camera glides instead of snapping after a jump", "%.2f m in one frame" % step)


## The camera must stay below the foliage line even at its steepest close-up
## angle, otherwise a nearby crown would fill the screen.
func _test_camera_clearance_under_canopy() -> void:
	var worst := 0.0
	for i in range(24):
		var d := lerpf(CameraRig.MIN_DISTANCE, CameraRig.DISTANCE, float(i) / 23.0)
		var close := clampf((CameraRig.CLOSE_RANGE - d) / (CameraRig.CLOSE_RANGE - CameraRig.MIN_DISTANCE), 0.0, 1.0)
		var pitch := deg_to_rad(CameraRig.PITCH_DEGREES - close * CameraRig.CLOSE_PITCH_LIFT)
		var height: float = CameraRig.FOCUS_HEIGHT + close * 0.65 + d * sin(-pitch)
		worst = maxf(worst, height)
	_check(worst < Forest.CANOPY_BOTTOM - 0.3, "camera stays below the canopy line", "max %.2f m vs foliage from %.2f m" % [worst, Forest.CANOPY_BOTTOM])


# ------------------------------------------------------------------- forest ---
func _test_forest_structure() -> void:
	var stage := Node3D.new()
	add_child(stage)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var info: Dictionary = Forest.build(stage, rng)

	_check(int(info["count"]) >= 70, "forest places a full stand of trees", "%d trees" % int(info["count"]))
	_check(int(info["far_count"]) > 0, "forest adds a distant treeline", "%d far trees" % int(info["far_count"]))
	_check(int(info["node_count"]) <= 20, "trees are instanced, not one node each", "%d nodes for %d trees" % [int(info["node_count"]), int(info["count"]) + int(info["far_count"])])
	_check(int(info["variant_count"]) >= 6, "forest offers several tree shapes", "%d variants" % int(info["variant_count"]))

	var positions: Array = info["positions"]
	var heights: Array = info["heights"]
	var closest := 1e9
	for i in range(positions.size()):
		for j in range(i + 1, positions.size()):
			closest = minf(closest, positions[i].distance_to(positions[j]))
	_check(closest >= Forest.MIN_SPACING - 0.01, "trunks keep a readable spacing", "closest pair %.2f m" % closest)

	var clearing_ok := true
	var start_ok := true
	var ruin_ok := true
	var hunter_spawn := Vector3(0, 0, 7)
	for p in positions:
		if Vector2(p.x, p.z).length() < Forest.INNER_RADIUS - 0.5:
			clearing_ok = false
		if p.distance_to(hunter_spawn) < Forest.START_CLEAR_RADIUS - 0.01:
			start_ok = false
		if p.distance_to(Forest.RUIN_CENTER) < Forest.RUIN_CLEAR_RADIUS - 0.01:
			ruin_ok = false
	_check(clearing_ok, "the starting clearing stays open")
	_check(start_ok, "no tree grows inside the hunter's spawn pocket", "%.1f m clear" % Forest.START_CLEAR_RADIUS)
	_check(ruin_ok, "the ruin courtyard stays clear", "%.1f m clear" % Forest.RUIN_CLEAR_RADIUS)

	var lowest: float = heights.min()
	var highest: float = heights.max()
	_check(highest - lowest > 2.5, "tree heights vary", "%.1f m to %.1f m" % [lowest, highest])

	var body: StaticBody3D = info["collision_body"]
	_check(body.collision_layer == Forest.COLLISION_LAYER and body.collision_mask == 0, "trunks only answer the camera's collision layer", "layer %d" % body.collision_layer)
	_check(int(info["collision_shapes"]) == int(info["count"]), "every trunk gets one collider", "%d colliders" % int(info["collision_shapes"]))

	stage.queue_free()
	await get_tree().process_frame


func _test_forest_determinism() -> void:
	var a := _forest_layout(20261030)
	var b := _forest_layout(20261030)
	var c := _forest_layout(7)
	_check(a == b, "the same seed reproduces the same forest")
	_check(a != c, "a different seed changes the forest")


func _forest_layout(seed_value: int) -> String:
	var stage := Node3D.new()
	add_child(stage)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var info: Dictionary = Forest.build(stage, rng)
	var parts := PackedStringArray()
	for p in info["positions"]:
		parts.append("%.3f,%.3f" % [p.x, p.z])
	for h in info["heights"]:
		parts.append("%.2f" % h)
	stage.queue_free()
	return ",".join(parts).sha256_text()


# -------------------------------------------------------------- environment ---
func _test_environment_and_ground() -> void:
	await _load_main()
	var info: Dictionary = _main.environment_info
	var env: Environment = info["environment"]
	_check(env != null, "scene builds a world environment")
	_check(env.fog_enabled and env.fog_density > 0.004 and env.fog_density < 0.02, "depth fog is present but restrained", "density %.4f" % env.fog_density)
	_check(env.tonemap_mode == Environment.TONE_MAPPER_FILMIC, "filmic tonemapping is active")
	_check(env.ambient_light_energy >= 0.6 and env.ambient_light_energy <= 1.4, "ambient light is balanced", "%.2f" % env.ambient_light_energy)

	var sun: DirectionalLight3D = info["sun"]
	var fill: DirectionalLight3D = info["fill"]
	_check(sun.shadow_enabled, "the sun casts shadows")
	_check(sun.shadow_blur > 0.0 and sun.shadow_opacity < 1.0, "shadows are soft and lifted", "blur %.1f, opacity %.2f" % [sun.shadow_blur, sun.shadow_opacity])
	_check(not fill.shadow_enabled, "the fill light costs no second shadow map")
	_check(sun.light_energy > 0.8 and sun.light_energy < 2.0, "sunlight stays in a readable range", "%.2f" % sun.light_energy)

	var ground_info: Dictionary = _main.ground_info
	var mat: StandardMaterial3D = ground_info["material"]
	_check(mat != null and mat.albedo_texture != null, "ground has a textured surface, not flat colour")
	_check(mat.normal_enabled and mat.normal_texture != null, "ground has surface detail from a normal map")
	_check(mat.roughness > 0.85, "ground is matte", "roughness %.2f" % mat.roughness)
	var body: StaticBody3D = ground_info["ground_body"]
	_check(body.get_child_count() >= 2 and body.collision_layer == 1, "the ground still collides with the hunter")


# -------------------------------------------------------------- deer marker ---
func _test_deer_marker() -> void:
	var marker = _main.deer_marker
	_check(marker != null, "scene builds the off-screen deer cue")
	var cam: Camera3D = _main.camera
	var forward: Vector3 = -cam.global_transform.basis.z

	_main.deer.global_position = cam.global_position + forward * 8.0
	marker.update_marker(cam, _main.deer.global_position, true)
	_check(not bool(marker.get("_visible_target")), "cue hides while the deer is close and in view")

	_main.deer.global_position = cam.global_position - forward * 20.0
	marker.update_marker(cam, _main.deer.global_position, true)
	_check(bool(marker.get("_visible_target")), "cue appears when the deer is behind the camera")

	_main.deer.global_position = cam.global_position + forward * 30.0
	marker.update_marker(cam, _main.deer.global_position, true)
	_check(bool(marker.get("_visible_target")) and bool(marker.get("_on_screen")), "a distant deer in view gets a marker, not a chevron")

	marker.update_marker(cam, _main.deer.global_position, false)
	_check(not bool(marker.get("_visible_target")), "cue hides when there is no deer to point at")


# -------------------------------------------------------- gameplay preserved ---
func _test_gameplay_preserved() -> void:
	await _load_main()
	var hunter = _main.hunter
	var start: Vector3 = hunter.global_position
	Input.action_press("move_forward")
	for _i in range(60):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var travelled := Vector2(hunter.global_position.x - start.x, hunter.global_position.z - start.z).length()
	var expected: float = MainScript.HUNTER_SPEED
	_check(absf(travelled - expected) < expected * 0.25, "hunter still moves at the tuned speed", "%.2f m in 1 s (expected %.2f)" % [travelled, expected])

	# Tree colliders must not block movement: walk straight through a trunk.
	var trees: Array = _main.forest_info["positions"]
	var trunk: Vector3 = trees[0]
	hunter.global_position = Vector3(trunk.x, 0.1, trunk.z + 2.0)
	hunter.velocity = Vector3.ZERO
	for _i in range(3):
		await get_tree().physics_frame
	var blocked_before: Vector3 = hunter.global_position
	hunter.global_position = Vector3(trunk.x, 0.1, trunk.z - 1.0)
	await get_tree().physics_frame
	_check(hunter.global_position.distance_to(Vector3(trunk.x, 0.1, trunk.z - 1.0)) < 0.5, "trunks do not block the hunter", "walked through (from z=%.1f)" % blocked_before.z)

	# The deer still notices and flees: the hunting loop is untouched. Since
	# Phase 3.2 detection also needs line of sight, this runs in the open
	# clearing rather than next to the trunk the hunter just walked through.
	_main.deer_ai.reset()
	hunter.global_position = Vector3(0, 0.1, 0)
	hunter.velocity = Vector3.ZERO
	_main.deer.global_position = Vector3(0, 0.1, -9.0)
	for _i in range(45):
		await get_tree().physics_frame
	_check(_main.deer_state in ["ALERTED", "FLEEING", "ESCAPING"], "deer still detects and reacts to the hunter", _main.deer_state)
	_check(_main.deer_rig != null and _main.hunter_rig != null, "the Phase 3 rigs are still in use")

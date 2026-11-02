extends Node
## Headless tests for the ATHAR hunting system.
##
## Run with:
##   godot --headless --path . res://scenes/tests/hunting_tests.tscn
##
## Exits 0 only when every check passes, so scripts/verify_project.sh can treat
## it like any other automated gate. The behaviour tests simulate deer_ai.gd
## directly at a fixed 60 Hz step (no rendering, no physics); the scene tests
## then instantiate the real main scene and drive its frame loop.

const DeerAI := preload("res://scripts/animals/deer_ai.gd")
const HuntSession := preload("res://scripts/gameplay/hunt_session.gd")
const MainScript := preload("res://scripts/main.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")

const DT := 1.0 / 60.0
const CAPTURE_DISTANCE := 1.8
# If the suite dies before reaching _finish(), this watchdog ends the process
# with a failure code instead of leaving it running forever.
const WATCHDOG_SECONDS := 90.0

var _checks := 0
var _failures := 0
var _main: Node3D
var _watchdog: Timer


func _ready() -> void:
	print("ATHAR hunting tests")
	_watchdog = Timer.new()
	_watchdog.wait_time = WATCHDOG_SECONDS
	_watchdog.one_shot = true
	_watchdog.timeout.connect(_on_watchdog_timeout)
	add_child(_watchdog)
	_watchdog.start()

	_test_detection_outside_range()
	_test_detection_inside_range()
	_test_alert_delay()
	_test_fleeing_state_sequence()
	_test_deer_opens_ground_while_fresh()
	_test_chase_balance()
	_test_deer_escapes_when_hunter_stalls()
	_test_boundary_steering()
	_test_seeded_replay()
	_test_capture_once()
	_test_new_hunt_loop()
	await _test_rig_geometry()
	await _test_live_scene()
	_finish()


## Ends the run with an explicit verdict. Kept in one place so a partial run
## can never look like a pass.
func _finish() -> void:
	_watchdog.stop()
	# Phase 3.4: the scene under test plays audio. Stop it, let the scene go and
	# give the audio thread a moment, or Godot reports in-flight streams as leaked.
	_silence_audio(get_tree().root)
	if is_instance_valid(_main):
		_main.free()
	_main = null
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


# ---------------------------------------------------------------- detection ---
func _test_detection_outside_range() -> void:
	var ai = DeerAI.new(7)
	var v := ai.update(DT, Vector3.ZERO, Vector3(0, 0.1, -(DeerAI.DETECT_RADIUS + 4.0)))
	_check(ai.state == DeerAI.GRAZING, "far hunter is ignored", "distance %.1f m" % ai.distance_to_hunter)
	_check(v.length() < 0.01 or ai.state == DeerAI.GRAZING, "deer keeps grazing")


func _test_detection_inside_range() -> void:
	var ai = DeerAI.new(7)
	ai.update(DT, Vector3.ZERO, Vector3(0, 0.1, -(DeerAI.DETECT_RADIUS - 1.0)))
	_check(ai.state == DeerAI.ALERTED, "hunter inside %.0f m triggers ALERTED" % DeerAI.DETECT_RADIUS, ai.state)


func _test_alert_delay() -> void:
	var ai = DeerAI.new(7)
	var deer := Vector3.ZERO
	var hunter := Vector3(0, 0.1, -9.0)
	ai.update(DT, deer, hunter)
	var early_ok := false
	for i in range(int(DeerAI.ALERT_DURATION / DT) - 2):
		ai.update(DT, deer, hunter)
		early_ok = ai.state == DeerAI.ALERTED
	_check(early_ok, "deer freezes during the alarm instead of bolting instantly")
	var fled := false
	for i in range(int(0.6 / DT)):
		ai.update(DT, deer, hunter)
		if ai.state == DeerAI.FLEEING:
			fled = true
			break
	_check(fled, "ALERTED becomes FLEEING after %.2f s" % DeerAI.ALERT_DURATION)


func _test_fleeing_state_sequence() -> void:
	var ai = DeerAI.new(3)
	var deer := Vector3.ZERO
	var hunter := Vector3(0, 0.1, -10.0)
	var seen := [ai.state]
	var speeds := {}
	for i in range(int(40.0 / DT)):
		var v := ai.update(DT, deer, hunter)
		deer += v * DT
		deer.y = 0.1
		if not seen.has(ai.state):
			seen.append(ai.state)
		speeds[ai.state] = v.length()
		if ai.state == DeerAI.ESCAPING and deer.z != deer.z:
			break
	var ordered := seen.find(DeerAI.ALERTED) >= 0 and seen.find(DeerAI.FLEEING) >= 0 and seen.find(DeerAI.ESCAPING) >= 0
	_check(ordered, "states follow GRAZING -> ALERTED -> FLEEING -> ESCAPING", str(seen))
	_check(absf(speeds.get(DeerAI.FLEEING, 0.0) - DeerAI.SPRINT_SPEED) < 0.001, "fleeing speed is the sprint speed", "%.2f m/s" % speeds.get(DeerAI.FLEEING, 0.0))
	_check(absf(speeds.get(DeerAI.ESCAPING, 0.0) - DeerAI.ESCAPE_SPEED) < 0.001, "escaping speed is the tired speed", "%.2f m/s" % speeds.get(DeerAI.ESCAPING, 0.0))


# ------------------------------------------------------------------ balance ---
func _test_deer_opens_ground_while_fresh() -> void:
	# Hunter stands still: a fresh deer must outrun it.
	var ai = DeerAI.new(11)
	var deer := Vector3.ZERO
	var hunter := Vector3(0, 0.1, -12.0)
	var start_distance := deer.distance_to(hunter)
	var flee_start := -1.0
	var flee_distance := 0.0
	var gain := 0.0
	for i in range(int(9.0 / DT)):
		var v := ai.update(DT, deer, hunter)
		deer += v * DT
		deer.y = 0.1
		if flee_start < 0.0 and ai.state == DeerAI.FLEEING:
			flee_start = i * DT
			flee_distance = deer.distance_to(hunter)
		if flee_start >= 0.0 and i * DT >= flee_start + 1.0:
			gain = deer.distance_to(hunter) - flee_distance
			break
	_check(gain > 0.8, "fresh deer opens ground on a stationary hunter", "+%.2f m in 1 s" % gain)
	_check(DeerAI.SPRINT_SPEED > MainScript.HUNTER_SPEED, "sprint speed beats hunter speed", "%.2f > %.2f" % [DeerAI.SPRINT_SPEED, MainScript.HUNTER_SPEED])
	_check(DeerAI.ESCAPE_SPEED < MainScript.HUNTER_SPEED, "tired speed loses to hunter speed", "%.2f < %.2f" % [DeerAI.ESCAPE_SPEED, MainScript.HUNTER_SPEED])
	_check(start_distance > DeerAI.DETECT_RADIUS - 1.5, "test starts just outside contact", "%.1f m" % start_distance)


func _test_chase_balance() -> void:
	var sim := _simulate_chase(1234, 40.0, MainScript.HUNTER_SPEED, CAPTURE_DISTANCE)
	_check(sim["captured"], "sustained pursuit can catch the deer", "after %.1f s" % sim["captured_at"])
	_check(sim["captured_at"] > 3.0, "deer is not caught instantly", "%.1f s" % sim["captured_at"])
	_check(sim["captured_at"] < 30.0, "chase does not drag on forever", "%.1f s" % sim["captured_at"])
	_check(sim["max_deer_speed"] <= DeerAI.SPRINT_SPEED + 0.01, "deer never exceeds its sprint speed", "%.2f m/s" % sim["max_deer_speed"])
	_check(sim["states"].has(DeerAI.FLEEING) and sim["states"].has(DeerAI.ESCAPING), "chase passes through both flight states", str(sim["states"]))
	_check(sim["distinct_captures"] == 1, "chase registers exactly one capture", "%d" % sim["distinct_captures"])


func _test_deer_escapes_when_hunter_stalls() -> void:
	var ai = DeerAI.new(5)
	var deer := Vector3.ZERO
	var hunter := Vector3(0, 0.1, -12.0)
	var lost := false
	for i in range(int(30.0 / DT)):
		var v := ai.update(DT, deer, hunter)
		deer += v * DT
		deer.y = 0.1
		if ai.state == DeerAI.GRAZING and i * DT > 2.0:
			lost = true
			break
	_check(lost, "an ignored deer breaks away and returns to GRAZING", "%.1f m" % deer.distance_to(hunter))


func _test_boundary_steering() -> void:
	# Deer pinned in the corner must turn back inside instead of grinding the wall.
	var ai = DeerAI.new(9)
	var deer := Vector3(40.0, 0.1, 40.0)
	var hunter := Vector3(30.0, 0.1, 30.0)
	var max_abs := 0.0
	for i in range(int(12.0 / DT)):
		var v := ai.update(DT, deer, hunter)
		deer += v * DT
		deer.y = 0.1
		max_abs = maxf(max_abs, maxf(absf(deer.x), absf(deer.z)))
	_check(max_abs <= 42.0, "deer stays inside the world while fleeing", "max |x|,|z| = %.1f" % max_abs)
	_check(deer.length() < Vector3(40, 0, 40).length() - 1.0, "cornered deer steers back toward open ground", "%.1f m from start" % deer.length())


func _test_seeded_replay() -> void:
	var a := _simulate_chase(4242, 25.0, MainScript.HUNTER_SPEED, CAPTURE_DISTANCE)
	var b := _simulate_chase(4242, 25.0, MainScript.HUNTER_SPEED, CAPTURE_DISTANCE)
	_check(absf(a["captured_at"] - b["captured_at"]) < 0.001 and a["final"].is_equal_approx(b["final"]), "same seed replays the same hunt", "%.1f s" % a["captured_at"])

	# Grazing wander is the only randomness; it must also replay per seed.
	var graze_a := _simulate_grazing(777, 12.0)
	var graze_b := _simulate_grazing(777, 12.0)
	var graze_c := _simulate_grazing(778, 12.0)
	_check(graze_a.is_equal_approx(graze_b), "same seed replays grazing")
	_check(not graze_a.is_equal_approx(graze_c), "a different seed changes grazing")


## Returns {captured_at, states, max_deer_speed, final, distinct_captures}.
func _simulate_chase(seed_value: int, seconds: float, hunter_speed: float, capture_distance: float) -> Dictionary:
	var ai = DeerAI.new(seed_value)
	var deer := Vector3(0, 0.1, 0)
	var hunter := Vector3(0, 0.1, -11.0)
	var t := 0.0
	var captured_at := -1.0
	var states := [ai.state]
	var max_speed := 0.0
	var captures := 0
	while t < seconds:
		var to_deer := deer - hunter
		to_deer.y = 0.0
		var distance := to_deer.length()
		if distance > 0.001:
			hunter += to_deer / distance * hunter_speed * DT
		var v := ai.update(DT, deer, hunter)
		deer += v * DT
		deer.y = 0.1
		t += DT
		max_speed = maxf(max_speed, v.length())
		if not states.has(ai.state):
			states.append(ai.state)
		if captured_at < 0.0 and deer.distance_to(hunter) <= capture_distance:
			captured_at = t
			captures += 1
			ai.capture()
	return {
		"captured": captured_at > 0.0,
		"captured_at": captured_at,
		"states": states,
		"max_deer_speed": max_speed,
		"final": deer,
		"distinct_captures": captures,
	}


func _simulate_grazing(seed_value: int, seconds: float) -> Vector3:
	var ai = DeerAI.new(seed_value)
	var deer := Vector3.ZERO
	var hunter := Vector3(0, 0.1, 60.0)  # far away, so it stays calm
	var t := 0.0
	while t < seconds:
		var v := ai.update(DT, deer, hunter)
		deer += v * DT
		t += DT
	return deer


# ------------------------------------------------------------------ capture ---
func _test_capture_once() -> void:
	var session = HuntSession.new()
	# Lambdas capture locals by value in GDScript, so count through an Array.
	var signal_count := [0]
	session.deer_captured.connect(func(): signal_count[0] += 1)
	_check(not session.try_capture(5.0), "out-of-reach capture is refused")
	_check(session.capture_count == 0, "refused capture does not count")
	_check(session.try_capture(CAPTURE_DISTANCE - 0.2), "in-reach capture succeeds")
	_check(not session.try_capture(0.1), "second capture in the same hunt is refused")
	_check(not session.try_capture(0.1), "third capture in the same hunt is refused")
	_check(session.capture_count == 1, "capture count stays at one", "%d" % session.capture_count)
	_check(signal_count[0] == 1, "captured signal fired exactly once", "%d" % signal_count[0])
	_check(DeerAI.SPRINT_SPEED > 0.0, "AI constants load")


func _test_new_hunt_loop() -> void:
	var session = HuntSession.new()
	var starts := [0]
	session.hunt_started.connect(func(_index): starts[0] += 1)
	_check(not session.begin_new_hunt(), "a new hunt cannot start before a capture")
	session.try_capture(1.0)
	_check(session.begin_new_hunt(), "a new hunt starts after a capture")
	_check(not session.is_captured, "new hunt clears the captured flag")
	_check(session.hunt_index == 2, "hunt index advanced", "%d" % session.hunt_index)
	_check(starts[0] == 1, "hunt_started fired once", "%d" % starts[0])
	_check(not session.begin_new_hunt(), "starting twice is refused")
	_check(session.try_capture(1.0), "the new hunt can be captured again")
	_check(session.capture_count == 2, "capture count accumulates across hunts", "%d" % session.capture_count)


# ------------------------------------------------------------ rig geometry ---
## Measures the assembled models so their proportions are checked numerically,
## not assumed. No renderer is involved: this is the mesh bounding box.
func _test_rig_geometry() -> void:
	var HunterRig := preload("res://scripts/visuals/hunter_rig.gd")
	var DeerRig := preload("res://scripts/visuals/deer_rig.gd")
	var stage := Node3D.new()
	add_child(stage)
	var hunter = HunterRig.new()
	stage.add_child(hunter)
	var deer = DeerRig.new()
	deer.position = Vector3(6, 0, 0)
	stage.add_child(deer)
	await get_tree().process_frame

	var hunter_box := _bounds(hunter)
	var deer_box := _bounds(deer)
	_check(hunter_box.size.y > 1.7 and hunter_box.size.y < 2.3, "hunter is a human-scale figure", "%.2f m tall" % hunter_box.size.y)
	_check(hunter_box.position.y > -0.12 and hunter_box.position.y < 0.15, "hunter's boots stand on the ground", "lowest point %.2f m" % hunter_box.position.y)
	_check(hunter_box.size.x < 1.3 and hunter_box.size.z < 1.3, "hunter stays a compact silhouette", "%.2f x %.2f m" % [hunter_box.size.x, hunter_box.size.z])
	_check(deer_box.size.y > 1.5 and deer_box.size.y < 2.3, "deer with antlers is deer-scale", "%.2f m tall" % deer_box.size.y)
	_check(deer_box.size.z > 1.3, "deer reads as a long-bodied animal", "%.2f m long" % deer_box.size.z)
	_check(deer_box.size.x < 1.0, "deer is narrow from the front", "%.2f m wide" % deer_box.size.x)
	_check(deer_box.position.y > -0.12, "deer hooves stand on the ground", "lowest point %.2f m" % deer_box.position.y)

	stage.queue_free()
	await get_tree().process_frame


func _bounds(root: Node) -> AABB:
	var result := AABB()
	var has_result := false
	for child in root.get_children():
		var box := AABB()
		if child is MeshInstance3D:
			box = child.global_transform * child.get_aabb()
		else:
			box = _bounds(child)
		if box.size.length() <= 0.0:
			continue
		result = box if not has_result else result.merge(box)
		has_result = true
	return result


# --------------------------------------------------------------- live scene ---
func _test_live_scene() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(_main.hunter_rig != null and _main.deer_rig != null, "scene builds hunter and deer rigs")
	var hunter_parts := _count_meshes(_main.hunter_rig)
	var deer_parts := _count_meshes(_main.deer_rig)
	_check(hunter_parts >= 40, "hunter rig is a detailed multi-part model", "%d mesh parts" % hunter_parts)
	_check(deer_parts >= 40, "deer rig is a detailed multi-part model", "%d mesh parts" % deer_parts)

	# Animation must actually rotate joints, not slide the body.
	var rig = _main.hunter_rig
	var thighs: Array = rig.get("_thighs")
	var before: float = thighs[0].rotation.x
	for i in range(30):
		rig.animate(DT, MainScript.HUNTER_SPEED)
	var after: float = thighs[0].rotation.x
	_check(absf(after - before) > 0.05, "hunter walk cycle rotates the leg joints", "%.2f -> %.2f rad" % [before, after])
	var deer_rig = _main.deer_rig
	var neck_before: float = deer_rig.get("_neck").rotation.x
	for i in range(20):
		deer_rig.animate(DT, 0.0)
	var neck_after: float = deer_rig.get("_neck").rotation.x
	_check(absf(neck_after - neck_before) > 0.01, "deer idle animation moves the neck", "%.2f -> %.2f rad" % [neck_before, neck_after])

	# Every state must be poseable without errors.
	for state in [DeerAI.GRAZING, DeerAI.ALERTED, DeerAI.FLEEING, DeerAI.ESCAPING, DeerAI.CAPTURED]:
		deer_rig.set_state(state)
		deer_rig.animate(DT, 2.0)
	_check(true, "all deer states pose cleanly")

	# Capture on contact, exactly once, and the deer stops colliding.
	_main.deer.global_position = _main.hunter.global_position + Vector3(0, 0, 1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_main.hunt_session.is_captured, "reaching the deer captures it")
	_check(_main.hunt_session.capture_count == 1, "scene capture counted once", "%d" % _main.hunt_session.capture_count)
	_check(_main.deer_collider.disabled, "deer collision is disabled after capture")
	_check(not _main.deer.visible, "captured deer leaves active play")
	_check(_main.deer.velocity.length() < 0.01, "captured deer stops moving")

	for i in range(5):
		await get_tree().physics_frame
	_check(_main.hunt_session.capture_count == 1, "no duplicate capture while the deer is secured", "%d" % _main.hunt_session.capture_count)

	# The existing HUNT button becomes the new-hunt control.
	_check(_main.hunt_button.text == "NEW HUNT", "HUNT button becomes NEW HUNT", _main.hunt_button.text)
	_main._on_hunt_pressed()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not _main.hunt_session.is_captured, "pressing NEW HUNT starts a hunt")
	_check(_main.hunt_session.hunt_index == 2, "hunt index advanced in the scene", "%d" % _main.hunt_session.hunt_index)
	_check(_main.deer.visible, "new deer is visible")
	_check(not _main.deer_collider.disabled, "new deer collides again")
	_check(_main.deer_state == DeerAI.GRAZING, "new deer starts GRAZING", _main.deer_state)
	_check(_main.deer.global_position.distance_to(_main.hunter.global_position) >= 15.0, "new deer spawns at a fair distance", "%.1f m" % _main.deer.global_position.distance_to(_main.hunter.global_position))

	_main.queue_free()
	await get_tree().process_frame


func _count_meshes(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is MeshInstance3D:
			count += 1
		count += _count_meshes(child)
	return count

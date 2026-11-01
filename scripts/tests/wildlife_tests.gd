extends Node
## Headless tests for the ATHAR wildlife AI (Phase 3.2).
##
## Run with:
##   godot --headless --path . res://scenes/tests/wildlife_tests.tscn
##
## Exits 0 only when every check passes, so scripts/verify_project.sh can treat
## it like the other suites. Everything here simulates deer_ai.gd directly at a
## fixed 60 Hz step with fake line-of-sight and navigation probes, so perception,
## memory and avoidance are tested without a renderer or real physics.
##
## The last group loads the real main scene to prove the AI is wired to it.

const DeerAI := preload("res://scripts/animals/deer_ai.gd")
const WildlifeProfile := preload("res://scripts/animals/wildlife_profile.gd")
const WildlifePerception := preload("res://scripts/animals/wildlife_perception.gd")
const WildlifeSteering := preload("res://scripts/animals/wildlife_steering.gd")
const HuntSession := preload("res://scripts/gameplay/hunt_session.gd")
const MainScript := preload("res://scripts/main.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")

const DT := 1.0 / 60.0
const WATCHDOG_SECONDS := 120.0

var _checks := 0
var _failures := 0
var _main: Node3D
var _watchdog: Timer


func _ready() -> void:
	print("ATHAR wildlife AI tests")
	_watchdog = Timer.new()
	_watchdog.wait_time = WATCHDOG_SECONDS
	_watchdog.one_shot = true
	_watchdog.timeout.connect(_on_watchdog_timeout)
	add_child(_watchdog)
	_watchdog.start()

	_test_layers()
	_test_calm_behaviour()
	_test_vision()
	_test_hearing()
	_test_memory()
	_test_alarm_flow()
	_test_flight_preserved()
	_test_avoidance()
	_test_personality()
	_test_determinism()
	_test_compatibility()
	await _test_live_scene()
	_finish()


func _finish() -> void:
	_watchdog.stop()
	print("")
	if _failures > 0:
		print("RESULT: %d checks, %d failed" % [_checks, _failures])
		get_tree().quit(1)
	else:
		print("RESULT: %d checks, 0 failed" % _checks)
		get_tree().quit(0)


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


# ------------------------------------------------------------------- helpers ---
## A probe that never blocks, i.e. open ground.
func _open() -> Callable:
	return func(_a: Vector3, _b: Vector3) -> bool: return false


## A probe that blocks any path crossing the z = `z` line.
func _wall(z: float) -> Callable:
	return func(from: Vector3, to: Vector3) -> bool:
		return (from.z - z) * (to.z - z) <= 0.0001


## Cover around a point: the target inside it is never in plain sight, but it
## can still be heard and approached.
func _bush(at: Vector3) -> Callable:
	return func(_from: Vector3, to: Vector3) -> bool: return to.distance_to(at) < 3.0


## The target is always in cover: it can be heard and approached, never seen.
func _obscured() -> Callable:
	return func(_from: Vector3, _to: Vector3) -> bool: return true


## Steps the AI with a stationary hunter. Returns the states seen, in order.
func _run(ai, seconds: float, deer: Vector3, hunter: Vector3, probe := Callable()) -> Dictionary:
	var states := [ai.state]
	var transitions := 0
	var previous: String = ai.state
	var min_dwell := INF
	var dwell := 0.0
	var steps := int(seconds / DT)
	for i in range(steps):
		var v: Vector3 = ai.update(DT, deer, hunter, probe)
		deer += v * DT
		deer.y = 0.1
		dwell += DT
		if ai.state != previous:
			transitions += 1
			min_dwell = minf(min_dwell, dwell)
			dwell = 0.0
			previous = ai.state
			if not states.has(ai.state):
				states.append(ai.state)
	return {"states": states, "transitions": transitions, "min_dwell": min_dwell, "deer": deer}


# -------------------------------------------------------------------- layers ---
func _test_layers() -> void:
	var ai = DeerAI.new(101)
	_check(ai.profile != null and ai.perception != null and ai.steering != null,
		"behaviour is split into profile, perception and steering layers")
	_check(ai.profile is WildlifeProfile, "profile is the reusable species blueprint")
	_check(ai.perception is WildlifePerception, "perception is the reusable sensing layer")
	_check(ai.steering is WildlifeSteering, "steering is the reusable movement layer")
	_check(ai.state == DeerAI.GRAZING, "a fresh deer starts calm", ai.state)
	_check(ai.activity_text() == "grazing", "state has a human-readable activity", ai.activity_text())
	_check(ai.profile.species == "deer", "profile knows its species", ai.profile.species)


# ------------------------------------------------------------- calm behaviour ---
func _test_calm_behaviour() -> void:
	var ai = DeerAI.new(202)
	var result := _run(ai, 40.0, Vector3.ZERO, Vector3(0, 0.1, 400.0))
	var states: Array = result["states"]
	var calm_variety := 0
	for s in [DeerAI.WANDERING, DeerAI.OBSERVING, DeerAI.RESTING]:
		if states.has(s):
			calm_variety += 1
	_check(states.has(DeerAI.GRAZING) and calm_variety >= 2,
		"an undisturbed deer cycles through grazing, watching and wandering", str(states))
	_check(result["transitions"] <= 14,
		"an undisturbed deer does not change state every frame", "%d changes in 40 s" % result["transitions"])
	_check(float(result["min_dwell"]) >= DeerAI.MIN_DWELL * 0.9,
		"every calm state is held for its minimum dwell", "shortest %.2f s" % float(result["min_dwell"]))
	_check(ai.is_calm(), "an undisturbed deer stays out of alarm states", ai.state)

	# Grazing really moves the animal; resting and watching do not.
	var grazer = DeerAI.new(303)
	var start: Vector3 = grazer.update(DT, Vector3.ZERO, Vector3(0, 0.1, 400.0))
	var moved := 0.0
	for i in range(120):
		var v: Vector3 = grazer.update(DT, Vector3.ZERO, Vector3(0, 0.1, 400.0))
		moved += v.length() * DT
	_check(moved > 1.0, "a grazing deer walks around its patch", "%.1f m in 2 s" % moved)

	# Calm states must never drift outside the world.
	var edge = DeerAI.new(404)
	var edge_result := _run(edge, 30.0, Vector3(39.5, 0.1, 39.5), Vector3(0, 0.1, 400.0))
	var far: Vector3 = edge_result["deer"]
	_check(maxf(absf(far.x), absf(far.z)) <= DeerAI.WORLD_LIMIT + 0.5,
		"a grazing deer drifts back inside the world", "max %.1f m" % maxf(absf(far.x), absf(far.z)))


# --------------------------------------------------------------------- vision ---
func _test_vision() -> void:
	var ai = DeerAI.new(505)
	ai.set_facing(Vector3(0, 0, -1))
	ai.update(DT, Vector3.ZERO, Vector3(0, 0.1, -12.5))
	_check(ai.perception.visible_now, "a hunter 12.5 m ahead is seen", "%.1f m" % ai.perception.distance)
	_check(ai.state == DeerAI.ALERTED, "seeing the hunter starts an alarm", ai.state)

	var far = DeerAI.new(505)
	far.set_facing(Vector3(0, 0, -1))
	far.update(DT, Vector3.ZERO, Vector3(0, 0.1, -20.0))
	_check(not far.perception.visible_now, "a hunter 20 m ahead is out of sight")
	_check(far.state == DeerAI.GRAZING, "an out-of-sight hunter leaves the deer calm", far.state)

	var behind = DeerAI.new(505)
	behind.set_facing(Vector3(0, 0, -1))
	behind.update(DT, Vector3.ZERO, Vector3(0, 0.1, 12.0))
	_check(not behind.perception.visible_now,
		"a hunter 12 m directly behind is outside the field of view",
		"angle %.0f deg" % behind.perception.angle_degrees)

	var close = DeerAI.new(505)
	close.set_facing(Vector3(0, 0, -1))
	close.update(DT, Vector3.ZERO, Vector3(0, 0.1, 6.0))
	_check(close.perception.visible_now, "a hunter 6 m behind is too close to miss")
	_check(close.state == DeerAI.ALERTED, "close contact wakes the deer even from behind", close.state)

	# Line of sight: a trunk between the two hides the hunter.
	var hidden = DeerAI.new(505)
	hidden.set_facing(Vector3(0, 0, -1))
	hidden.update(DT, Vector3.ZERO, Vector3(0, 0.1, -9.0), _wall(-4.5))
	_check(not hidden.perception.visible_now, "a trunk between deer and hunter blocks sight")
	_check(hidden.state == DeerAI.GRAZING, "an unseen hunter does not alarm the deer", hidden.state)

	var blocked_close = DeerAI.new(505)
	blocked_close.set_facing(Vector3(0, 0, -1))
	blocked_close.update(DT, Vector3.ZERO, Vector3(0, 0.1, -5.0), _wall(-2.5))
	_check(not blocked_close.perception.visible_now, "cover works at close range too")

	_check(ai.profile.vision_angle >= 200.0 and ai.profile.vision_angle <= 340.0,
		"field of view is panoramic but not all-round", "%.0f deg" % ai.profile.vision_angle)
	_check(ai.profile.vision_range == DeerAI.DETECT_RADIUS,
		"personality never moves the tuned detection distance", "%.1f m" % ai.profile.vision_range)


# -------------------------------------------------------------------- hearing ---
func _test_hearing() -> void:
	# The hunter is behind the deer (outside its view) and moving.
	var ai = DeerAI.new(606)
	ai.set_facing(Vector3(0, 0, -1))
	var reach: float = ai.profile.hearing_range - 2.0
	var heard := _walk_hunter(ai, reach, 4.4)
	_check(bool(heard["heard"]), "a running hunter is heard from behind", "%.1f m away" % reach)
	_check(heard["state"] in [DeerAI.ALERTED, DeerAI.INVESTIGATING],
		"a running hunter behind the deer causes an alarm", str(heard["state"]))

	var quiet = DeerAI.new(606)
	quiet.set_facing(Vector3(0, 0, -1))
	var quiet_reach: float = quiet.profile.hearing_range + 4.0
	var not_heard := _walk_hunter(quiet, quiet_reach, 4.4)
	_check(not bool(not_heard["heard"]), "a running hunter beyond earshot is not heard", "%.1f m away" % quiet_reach)

	var walker = DeerAI.new(606)
	walker.set_facing(Vector3(0, 0, -1))
	var walked := _walk_hunter(walker, walker.profile.hearing_range - 2.0, 1.0)
	_check(not bool(walked["heard"]), "a walking hunter at that range is not heard",
		"noise %.2f" % walked["noise"])

	var still = DeerAI.new(606)
	still.set_facing(Vector3(0, 0, -1))
	for i in range(60):
		still.update(DT, Vector3.ZERO, Vector3(0, 0.1, 8.0))
	_check(not still.perception.heard_now, "a standing hunter makes no sound")
	_check(still.state in [DeerAI.ALERTED, DeerAI.FLEEING], "a visible standing hunter is still seen", still.state)

	# Beyond the deer's view (behind cover), quiet movement is still heard, and
	# must not by itself startle the deer into flight.
	var close_walk = DeerAI.new(606)
	close_walk.set_facing(Vector3(0, 0, -1))
	var footsteps := _walk_hunter(close_walk, 4.0, 1.0, _bush(Vector3(0, 0.1, 4.0)))
	_check(bool(footsteps["heard"]), "quiet footsteps behind cover are still heard",
		"%.1f m away" % 4.0)
	_check(footsteps["state"] in [DeerAI.GRAZING, DeerAI.WANDERING, DeerAI.OBSERVING, DeerAI.RESTING],
		"quiet footsteps do not trigger an alarm by themselves", str(footsteps["state"]))

	_check(DeerAI.NOISE_ALERT_LEVEL > 0.0 and DeerAI.NOISE_ALERT_LEVEL < 1.0,
		"there is a noise threshold below which the deer stays calm", "%.2f" % DeerAI.NOISE_ALERT_LEVEL)


## Moves a hunter tangentially behind the deer at `speed` for long enough for the
## deer's speed estimate to settle, then reports what the deer perceived.
func _walk_hunter(ai, distance: float, speed: float, probe := Callable()) -> Dictionary:
	var hunter := Vector3(0, 0.1, distance)
	for i in range(45):
		hunter.x += speed * DT
		ai.update(DT, Vector3.ZERO, hunter, probe)
	return {
		"heard": ai.perception.heard_now,
		"noise": ai.perception.noise_level,
		"state": ai.state,
	}


# --------------------------------------------------------------------- memory ---
func _test_memory() -> void:
	var ai = DeerAI.new(707)
	ai.set_facing(Vector3(0, 0, -1))
	ai.update(DT, Vector3.ZERO, Vector3(0, 0.1, -8.0))
	_check(ai.threat_known, "a sighting is remembered")
	_check(ai.perception.threat_position.distance_to(Vector3(0, 0.1, -8.0)) < 0.01,
		"memory stores the threat's position")

	# Hide behind cover: the deer keeps the memory for a while.
	var cover := _wall(-4.0)
	var hidden_for := 1.0
	var steps := int(hidden_for / DT)
	for i in range(steps):
		ai.update(DT, Vector3.ZERO, Vector3(0, 0.1, -8.0), cover)
	_check(not ai.perception.visible_now, "cover hides the hunter", "visible=%s" % ai.perception.visible_now)
	_check(ai.threat_known, "the deer still remembers the threat after 1 s out of sight",
		"memory %.1f s left" % ai.perception.memory_left)
	_check(ai.state != DeerAI.GRAZING, "a deer with a remembered threat has not relaxed yet", ai.state)

	# Memory must expire.
	var waited := 0.0
	while ai.threat_known and waited < 30.0:
		ai.update(DT, Vector3.ZERO, Vector3(0, 0.1, -8.0), cover)
		waited += DT
	_check(not ai.threat_known, "threat memory expires when the hunter stays away",
		"forgotten after %.1f s" % (hidden_for + waited))
	_check(waited > 1.0, "memory does not expire instantly", "%.1f s" % waited)

	# A seen threat refreshes the memory clock.
	var refreshed = DeerAI.new(707)
	refreshed.set_facing(Vector3(0, 0, -1))
	refreshed.update(DT, Vector3.ZERO, Vector3(0, 0.1, -8.0))
	refreshed.perception.memory_left = 0.5
	refreshed.update(DT, Vector3.ZERO, Vector3(0, 0.1, -8.0))
	_check(refreshed.perception.memory_left > 0.5, "seeing the threat again refreshes the memory",
		"%.1f s" % refreshed.perception.memory_left)


# ----------------------------------------------------------------- alarm flow ---
func _test_alarm_flow() -> void:
	# Close threat after the freeze: flight.
	var close = DeerAI.new(808)
	close.set_facing(Vector3(0, 0, -1))
	var fled := false
	for i in range(int(3.0 / DT)):
		close.update(DT, Vector3.ZERO, Vector3(0, 0.1, -8.5))
		if close.state == DeerAI.FLEEING:
			fled = true
			break
	_check(fled, "a close threat after the freeze turns into flight")

	# Distant but confirmed threat: investigate before running.
	var far = DeerAI.new(808)
	far.set_facing(Vector3(0, 0, -1))
	var investigated := false
	for i in range(int(3.0 / DT)):
		far.update(DT, Vector3.ZERO, Vector3(0, 0.1, -12.5))
		if far.state == DeerAI.INVESTIGATING:
			investigated = true
			break
	_check(investigated, "a threat at the edge of sight is investigated, not fled from", far.state)
	_check(far.profile.confirm_distance < far.profile.vision_range,
		"there is a band between investigating and fleeing",
		"confirm %.1f m vs sight %.1f m" % [far.profile.confirm_distance, far.profile.vision_range])

	# Investigating: a sound behind cover draws the deer closer, then it gives up.
	# The bush keeps the hunter out of sight, so only hearing is involved.
	var approach = DeerAI.new(808)
	approach.set_facing(Vector3(0, 0, -1))
	var bush := _obscured()
	var deer := Vector3.ZERO
	var hunter := Vector3(0, 0.1, 12.0)
	for i in range(int(2.0 / DT)):
		hunter.x += 4.4 * DT  # a running hunter, heard but never seen
		var v: Vector3 = approach.update(DT, deer, hunter, bush)
		deer += v * DT
		deer.y = 0.1
	_check(approach.state == DeerAI.INVESTIGATING, "a heard-only threat is investigated, not fled", approach.state)

	# The noise stops. The deer walks toward where it last heard it.
	var spot: Vector3 = approach.perception.threat_position
	var start_distance := deer.distance_to(spot)
	for i in range(int(1.0 / DT)):
		var v: Vector3 = approach.update(DT, deer, hunter, bush)
		deer += v * DT
		deer.y = 0.1
	_check(deer.distance_to(spot) < start_distance - 0.3, "an investigating deer closes in to look",
		"%.1f m -> %.1f m" % [start_distance, deer.distance_to(spot)])

	# Nothing more happens: the investigation must end on its own.
	var settled := _run(approach, 20.0, deer, hunter, bush)
	_check(approach.is_calm(), "investigation ends on its own once nothing more happens", approach.state)
	_check(not settled["states"].has(DeerAI.FLEEING), "a heard-only threat never became a chase", str(settled["states"]))

	# Returning: walk home, then graze again.
	var back = DeerAI.new(808)
	var home := Vector3(0, 0.1, 0)
	back.update(DT, home, Vector3(0, 0.1, 400.0))
	back.perception.memory_left = 0.0
	var lost := _run(back, 25.0, Vector3(20.0, 0.1, 20.0), Vector3(0, 0.1, 400.0))
	_check(lost["states"].has(DeerAI.RETURNING) or lost["states"].has(DeerAI.GRAZING),
		"a deer with no threat returns to normal behaviour", str(lost["states"]))
	_check(back.is_calm(), "the deer relaxes after the danger is gone", back.state)

	# Re-alarm while returning.
	var wary = DeerAI.new(909)
	wary.set_facing(Vector3(0, 0, -1))
	wary.update(DT, Vector3.ZERO, Vector3(0, 0.1, -8.0))
	for i in range(int(30.0 / DT)):
		# Hunter walks away quietly and out of sight.
		wary.update(DT, Vector3.ZERO, Vector3(0, 0.1, -60.0))
		if wary.state == DeerAI.RETURNING:
			break
	var before: String = wary.state
	wary.update(DT, Vector3.ZERO, Vector3(0, 0.1, -6.0))
	_check(wary.state == DeerAI.ALERTED and before == DeerAI.RETURNING,
		"a returning deer re-alerts if the hunter reappears", "%s -> %s" % [before, wary.state])


# --------------------------------------------------------------- flight rules ---
func _test_flight_preserved() -> void:
	var ai = DeerAI.new(111)
	ai.set_facing(Vector3(0, 0, -1))
	var deer := Vector3.ZERO
	var hunter := Vector3(0, 0.1, -9.0)
	var max_speed := 0.0
	var max_step := 0.0
	var reached_sprint := false
	var reached_escape := false
	for i in range(int(30.0 / DT)):
		var v: Vector3 = ai.update(DT, deer, hunter)
		max_speed = maxf(max_speed, v.length())
		max_step = maxf(max_step, v.length() * DT)
		deer += v * DT
		deer.y = 0.1
		if ai.state == DeerAI.FLEEING and absf(ai.speed - DeerAI.SPRINT_SPEED) < 0.01:
			reached_sprint = true
		if ai.state == DeerAI.ESCAPING:
			reached_escape = true
	_check(reached_sprint, "flight reaches the tuned sprint speed", "%.2f m/s" % DeerAI.SPRINT_SPEED)
	_check(reached_escape, "flight still tires into the escape speed", "%.2f m/s" % DeerAI.ESCAPE_SPEED)
	_check(max_speed <= DeerAI.SPRINT_SPEED + 0.01, "the deer never exceeds its sprint speed",
		"%.2f m/s" % max_speed)
	_check(max_step <= DeerAI.SPRINT_SPEED * DT + 0.02, "the deer never teleports", "%.3f m per frame" % max_step)
	_check(DeerAI.SPRINT_SPEED > MainScript.HUNTER_SPEED and DeerAI.ESCAPE_SPEED < MainScript.HUNTER_SPEED,
		"chase balance constants are untouched",
		"%.1f / %.1f / %.1f" % [DeerAI.SPRINT_SPEED, MainScript.HUNTER_SPEED, DeerAI.ESCAPE_SPEED])

	# Breaking away goes through RETURNING before grazing again.
	var escape = DeerAI.new(112)
	escape.set_facing(Vector3(0, 0, -1))
	var states := [escape.state]
	var far_deer := Vector3.ZERO
	for i in range(int(40.0 / DT)):
		var v: Vector3 = escape.update(DT, far_deer, Vector3(0, 0.1, -12.0))
		far_deer += v * DT
		if not states.has(escape.state):
			states.append(escape.state)
	_check(states.has(DeerAI.RETURNING), "a deer that breaks away settles instead of snapping to grazing", str(states))
	_check(states.has(DeerAI.GRAZING), "the deer eventually grazes again", str(states))


# ----------------------------------------------------------------- avoidance ---
func _test_avoidance() -> void:
	var ai = DeerAI.new(121)
	ai.set_facing(Vector3(0, 0, -1))
	var deer := Vector3.ZERO
	var hunter := Vector3(0, 0.1, -9.0)
	var travelled := 0.0
	var last: Vector3 = deer
	for i in range(int(6.0 / DT)):
		var v: Vector3 = ai.update(DT, deer, hunter)
		deer += v * DT
		deer.y = 0.1
		travelled += last.distance_to(deer)
		last = deer
	_check(travelled > 10.0, "a fleeing deer covers ground without a navigation probe",
		"%.1f m in 6 s" % travelled)
	_check(deer.x == deer.x and deer.z == deer.z, "no NaN or infinity without a probe")

	# A trunk directly in the flight path must be stepped around.
	var direct := Vector3(0, 0, -1)
	var blocked = DeerAI.new(122)
	blocked.set_facing(direct)
	var avoided: Vector3 = blocked.steering.avoid(Vector3.ZERO, direct, DT, 2.8, 0.45, _wall(-1.5))
	_check(avoided.length_squared() > 0.0 and absf(avoided.angle_to(direct)) > 0.17,
		"the deer steers aside when a trunk blocks its path",
		"%.0f deg off course" % rad_to_deg(absf(avoided.angle_to(direct))))

	# The detour it picks must actually be clear.
	var wall_probe := _wall(-1.5)
	var chooser = DeerAI.new(123)
	chooser.set_facing(Vector3(0, 0, -1))
	var picked: Vector3 = chooser.steering.avoid(Vector3.ZERO, Vector3(0, 0, -1), DT, 2.8, 0.45, wall_probe)
	_check(not bool(wall_probe.call(Vector3.ZERO, Vector3.ZERO + picked * 2.8)),
		"the chosen detour is actually open ground", "heading offset %.0f deg" % rad_to_deg(picked.angle_to(Vector3(0, 0, -1))))

	# It must commit to one side rather than weaving.
	var side_changes := 0
	var previous_side: int = chooser.steering.facing_side()
	for i in range(90):
		chooser.steering.avoid(Vector3.ZERO, Vector3(0, 0, -1), DT, 2.8, 0.45, wall_probe)
		if chooser.steering.facing_side() != previous_side:
			side_changes += 1
			previous_side = chooser.steering.facing_side()
	_check(side_changes <= 1, "the deer commits to one way around an obstacle", "%d side changes" % side_changes)

	# Cornered against a wall it cannot pass, the deer must run along it, not stop.
	# The hunter sits behind the deer, so the flight course is straight into the
	# wall at z = +6.
	var runner = DeerAI.new(124)
	runner.set_facing(Vector3(0, 0, -1))
	runner.set_navigation_probe(_wall(6.0))
	var pos := Vector3.ZERO
	var hunter_close := Vector3(0, 0.1, -9.0)
	var lateral := 0.0
	for i in range(int(6.0 / DT)):
		var v: Vector3 = runner.update(DT, pos, hunter_close)
		pos += v * DT
		pos.y = 0.1
		lateral = maxf(lateral, absf(pos.x))
	_check(absf(pos.z) < 6.4, "the deer does not run through the wall", "z = %.1f m" % pos.z)
	_check(lateral > 2.0, "the deer goes around the wall instead of into it", "%.1f m to the side" % lateral)
	_check(runner.speed > 0.2, "the deer keeps its speed while routing around cover", "%.2f m/s" % runner.speed)

	_check(DeerAI.AVOID_LOOKAHEAD > 1.0 and DeerAI.AVOID_REFRESH > 0.0,
		"avoidance is bounded in distance and refreshed on a timer",
		"%.1f m, %.2f s" % [DeerAI.AVOID_LOOKAHEAD, DeerAI.AVOID_REFRESH])


# --------------------------------------------------------------- personality ---
func _test_personality() -> void:
	var archetypes := {}
	var memories := {}
	var hearings := {}
	var profiles := {}
	for seed_value in range(1, 61):
		var p = DeerAI.new(seed_value).profile
		archetypes[p.archetype] = true
		memories[p.archetype] = p.memory_time
		hearings[p.archetype] = p.hearing_range
		profiles[seed_value] = p
	_check(archetypes.size() == 4, "seeded generation produces every temperament",
		", ".join(archetypes.keys()))
	_check(memories.size() >= 3, "temperaments differ in how long they remember a threat",
		"e.g. %.1f s" % memories.values()[0])
	_check(hearings.size() >= 3, "temperaments differ in how well they hear",
		"e.g. %.1f m" % hearings.values()[0])
	_check(memories.values().max() - memories.values().min() > 1.0,
		"the memory spread is noticeable", "%.1f s" % (memories.values().max() - memories.values().min()))

	var again = DeerAI.new(4).profile
	var first = profiles[4]
	_check(again.archetype == first.archetype and absf(again.memory_time - first.memory_time) < 0.0001,
		"the same seed always gives the same animal", again.archetype)
	var other = DeerAI.new(5).profile
	_check(other.archetype != first.archetype or absf(other.memory_time - first.memory_time) > 0.0001,
		"a different seed gives a different animal", "%s vs %s" % [first.archetype, other.archetype])

	var same_speeds := absf(DeerAI.SPRINT_SPEED - 5.6) < 0.0001 and absf(DeerAI.ESCAPE_SPEED - 3.4) < 0.0001 and absf(DeerAI.GRAZE_SPEED - 1.05) < 0.0001
	_check(same_speeds, "personality never changes the movement speeds")

	# Fairness: every temperament can still be caught, in the tuned window.
	var captured_by_archetype := {}
	for seed_value in range(1, 41):
		var archetype: String = profiles.get(seed_value).archetype if profiles.has(seed_value) else ""
		if archetype == "" or captured_by_archetype.has(archetype):
			continue
		var sim := _simulate_chase(seed_value, 40.0)
		captured_by_archetype[archetype] = sim
		_check(bool(sim["captured"]) and float(sim["captured_at"]) > 3.0 and float(sim["captured_at"]) < 30.0,
			"a %s deer is still catchable in a fair chase" % archetype,
			"%.1f s" % float(sim["captured_at"]))
	_check(captured_by_archetype.size() == 4, "all four temperaments were chase-tested",
		", ".join(captured_by_archetype.keys()))


## Runs the same pursuit model as the hunting suite: hunter closes at its tuned
## speed, capture at 1.8 m.
func _simulate_chase(seed_value: int, seconds: float) -> Dictionary:
	var ai = DeerAI.new(seed_value)
	var deer := Vector3(0, 0.1, 0)
	var hunter := Vector3(0, 0.1, -11.0)
	var t := 0.0
	var captured_at := -1.0
	while t < seconds:
		var to_deer := deer - hunter
		to_deer.y = 0.0
		var distance := to_deer.length()
		if distance > 0.001:
			hunter += to_deer / distance * MainScript.HUNTER_SPEED * DT
		var v: Vector3 = ai.update(DT, deer, hunter)
		deer += v * DT
		deer.y = 0.1
		t += DT
		if captured_at < 0.0 and deer.distance_to(hunter) <= 1.8:
			captured_at = t
			ai.capture()
	return {"captured": captured_at > 0.0, "captured_at": captured_at}


# --------------------------------------------------------------- determinism ---
func _test_determinism() -> void:
	var a := _scripted_run(2024)
	var b := _scripted_run(2024)
	var c := _scripted_run(2025)
	_check(a["states"] == b["states"] and a["final"].is_equal_approx(b["final"]),
		"the same seed replays the same behaviour", "%d states" % a["states"].size())
	_check(a["final"].is_equal_approx(c["final"]) == false,
		"a different seed changes the behaviour", "%.2f m apart" % a["final"].distance_to(c["final"]))
	_check(a["states"].size() > 2, "the scripted run exercised several states", str(a["states"]))


## Fixed hunter path so any divergence comes from the deer's own randomness.
func _scripted_run(seed_value: int) -> Dictionary:
	var ai = DeerAI.new(seed_value)
	var deer := Vector3.ZERO
	var hunter := Vector3(0, 0.1, -14.0)
	var states := [ai.state]
	var t := 0.0
	while t < 24.0:
		var step := Vector3(sin(t * 0.7), 0.0, cos(t * 0.5)) * MainScript.HUNTER_SPEED * DT
		hunter += step
		var v: Vector3 = ai.update(DT, deer, hunter)
		deer += v * DT
		deer.y = 0.1
		t += DT
		if not states.has(ai.state):
			states.append(ai.state)
	return {"states": states, "final": deer}


# --------------------------------------------------------------- compatibility ---
func _test_compatibility() -> void:
	var ai = DeerAI.new(313)
	ai.set_facing(Vector3(0, 0, -1))
	var emissions := [0]
	ai.state_changed.connect(func(_p, _c): emissions[0] += 1)
	ai.update(DT, Vector3.ZERO, Vector3(0, 0.1, -8.0))
	_check(emissions[0] == 1, "state_changed fires once per transition", "%d" % emissions[0])
	ai.capture()
	_check(ai.state == DeerAI.CAPTURED and ai.is_captured(), "capture puts the deer in CAPTURED")
	var after: Vector3 = ai.update(DT, Vector3.ZERO, Vector3(0, 0.1, -1.0))
	_check(after == Vector3.ZERO, "a captured deer stops moving")
	ai.capture()
	_check(emissions[0] == 2, "capturing twice does not re-fire the signal", "%d" % emissions[0])

	ai.reset()
	_check(ai.state == DeerAI.GRAZING and ai.stamina == 1.0, "reset returns the deer to a calm, rested state")
	_check(not ai.threat_known and ai.perception.memory_left == 0.0, "reset clears threat memory")

	# The hunt loop still works with the richer brain.
	var session = HuntSession.new()
	var captures := [0]
	session.deer_captured.connect(func(): captures[0] += 1)
	_check(session.try_capture(1.5), "a hunt can still capture the deer")
	_check(not session.try_capture(1.5), "capture stays single-shot")
	_check(session.begin_new_hunt(), "a new hunt can still start")
	ai.reset()
	_check(ai.state == DeerAI.GRAZING, "a new hunt puts the deer back to grazing")
	_check(session.capture_count == 1, "only one capture was counted", "%d" % session.capture_count)


func _test_live_scene() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(_main.deer_ai.profile != null and _main.deer_ai.perception != null,
		"the live scene uses the layered wildlife brain")
	_check(_main.deer_ai.profile.archetype in WildlifeProfile.ARCHETYPES,
		"the live deer has a temperament", _main.deer_ai.profile.archetype)

	# Put both in the open, nine metres apart, and let the scene run.
	_main.hunter.global_position = Vector3(0, 0.1, 0)
	_main.hunter.velocity = Vector3.ZERO
	_main.deer_ai.reset()
	_main.deer.global_position = Vector3(0, 0.1, -9.0)
	_main.deer.velocity = Vector3.ZERO
	var start: Vector3 = _main.deer.global_position
	for i in range(120):
		await get_tree().physics_frame
	_check(_main.deer_state in [DeerAI.ALERTED, DeerAI.FLEEING, DeerAI.ESCAPING],
		"the live deer notices a hunter standing in the open", _main.deer_state)
	_check(_main.deer.global_position.distance_to(_main.hunter.global_position) > start.distance_to(_main.hunter.global_position),
		"the live deer moves away once alarmed",
		"%.1f m -> %.1f m" % [start.distance_to(_main.hunter.global_position), _main.deer.global_position.distance_to(_main.hunter.global_position)])

	# Every state the brain can produce must pose cleanly on the rig.
	var missing := []
	for state in [DeerAI.GRAZING, DeerAI.WANDERING, DeerAI.OBSERVING, DeerAI.RESTING,
			DeerAI.ALERTED, DeerAI.INVESTIGATING, DeerAI.FLEEING, DeerAI.ESCAPING,
			DeerAI.RETURNING, DeerAI.CAPTURED]:
		if not DeerAI.ACTIVITY_TEXT.has(state):
			missing.append(state)
		_main.deer_rig.set_state(state)
		_main.deer_rig.animate(DT, 2.0)
	_check(missing.is_empty(), "every AI state maps to a pose and a HUD verb", str(missing))

	_main.deer.global_position = _main.hunter.global_position + Vector3(0, 0, 1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_main.hunt_session.is_captured, "walking into the live deer still captures it")
	_main.queue_free()
	await get_tree().process_frame

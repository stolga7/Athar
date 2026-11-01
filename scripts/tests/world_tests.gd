extends Node
## Headless tests for the living world (Phase 3.3): the clock, weather, wind,
## rain and the wildlife's reaction to them.
##
## Run with:
##   godot --headless --path . res://scenes/tests/world_tests.tscn
##
## The day cycle and the weather are pure logic, so most of this steps them
## directly at 60 Hz. The last groups load the real scene and drive it by hand,
## which is how the lighting, shader parameters and rain emitter are checked
## without a renderer.

const DayCycle := preload("res://scripts/world/day_cycle.gd")
const Weather := preload("res://scripts/world/weather.gd")
const Rain := preload("res://scripts/world/rain.gd")
const LivingWorld := preload("res://scripts/world/living_world.gd")
const DeerAI := preload("res://scripts/animals/deer_ai.gd")
const MainScript := preload("res://scripts/main.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")

const DT := 1.0 / 60.0
const WATCHDOG_SECONDS := 120.0

var _checks := 0
var _failures := 0
var _main: Node3D
var _watchdog: Timer


func _ready() -> void:
	print("ATHAR living world tests")
	_watchdog = Timer.new()
	_watchdog.wait_time = WATCHDOG_SECONDS
	_watchdog.one_shot = true
	_watchdog.timeout.connect(_on_watchdog_timeout)
	add_child(_watchdog)
	_watchdog.start()

	_test_clock()
	_test_day_light()
	_test_day_continuity()
	_test_weather()
	_test_weather_determinism()
	_test_wildlife_modifiers()
	await _test_scene()
	await _test_scene_night_and_rain()
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


# --------------------------------------------------------------------- clock ---
func _test_clock() -> void:
	var clock = DayCycle.new()
	_check(absf(clock.time_of_day - DayCycle.START_TIME) < 0.0001,
		"a new day starts at the configured hour", clock.clock_text())

	var before: float = clock.time_of_day
	clock.advance(24.0)
	_check(absf(clock.time_of_day - before - 24.0 / DayCycle.SECONDS_PER_DAY) < 0.0001,
		"the clock advances with real time", "%s -> %s" % [clock.clock_text(), clock.clock_text()])

	clock.set_time(0.99)
	clock.advance(DayCycle.SECONDS_PER_DAY * 0.02)
	_check(clock.time_of_day < 0.05, "the clock wraps past midnight", "%.3f" % clock.time_of_day)

	var labels := {}
	for t in [0.0, 0.10, 0.25, 0.35, 0.55, 0.72, 0.80, 0.95]:
		clock.set_time(t)
		labels[t] = clock.phase()
	_check(labels[0.0] == "night" and labels[0.10] == "night", "midnight and late night are night", str(labels[0.0]))
	_check(labels[0.25] == "dawn", "sunrise is dawn", labels[0.25])
	_check(labels[0.35] == "day" and labels[0.55] == "day", "midday is day", labels[0.55])
	_check(labels[0.72] == "dusk", "sunset is dusk", labels[0.72])
	_check(labels[0.95] == "night", "after dusk is night again", labels[0.95])

	clock.set_time(0.5)
	_check(clock.clock_text() == "12:00", "noon reads as 12:00", clock.clock_text())
	clock.set_time(0.0)
	_check(clock.clock_text() == "00:00", "midnight reads as 00:00", clock.clock_text())

	# Crossing each boundary must report the change, so the scene can react.
	var crossings := [
		[DayCycle.PHASE_DAWN - 0.002, 0.002],
		[DayCycle.PHASE_MORNING - 0.002, 0.002],
		[DayCycle.PHASE_EVENING - 0.002, 0.002],
		[DayCycle.PHASE_NIGHT - 0.002, 0.002],
	]
	var reported := 0
	for pair in crossings:
		clock.set_time(float(pair[0]))
		if clock.advance(float(pair[1]) * DayCycle.SECONDS_PER_DAY):
			reported += 1
	_check(reported == 4, "every phase boundary is reported to the scene", "%.0f/4" % reported)


# ---------------------------------------------------------------- day light ---
func _test_day_light() -> void:
	var clock = DayCycle.new()

	clock.set_time(0.5)
	var noon: Dictionary = clock.sample()
	_check(absf(float(noon["sun_energy"]) - 1.55) < 0.02, "noon keeps the approved sun energy",
		"%.2f" % float(noon["sun_energy"]))
	_check(absf(float(noon["ambient_energy"]) - 1.00) < 0.02, "noon keeps the approved ambient light",
		"%.2f" % float(noon["ambient_energy"]))
	_check(absf(float(noon["fog_density"]) - 0.0095) < 0.0005, "noon keeps the approved fog density",
		"%.4f" % float(noon["fog_density"]))
	_check(absf(float(noon["daylight"]) - 1.0) < 0.01 and float(noon["night"]) < 0.01,
		"noon is full daylight")
	var rotation: Vector3 = noon["sun_rotation"]
	_check(absf(rotation.x + 44.0) < 0.5, "the noon sun sits at the approved elevation",
		"%.1f deg" % rotation.x)

	clock.set_time(0.25)
	var dawn: Dictionary = clock.sample()
	_check(float(dawn["twilight"]) > 0.9, "sunrise is a twilight moment", "%.2f" % float(dawn["twilight"]))
	_check(float(dawn["sun_energy"]) > 0.2, "dawn still lights the world", "%.2f" % float(dawn["sun_energy"]))
	var dawn_sun: Color = dawn["sun_color"]
	_check(dawn_sun.r > dawn_sun.b, "dawn light is warm", str(dawn_sun))

	clock.set_time(0.75)
	var dusk: Dictionary = clock.sample()
	var dusk_sun: Color = dusk["sun_color"]
	_check(float(dusk["twilight"]) > 0.9, "sunset is a twilight moment")
	_check(dusk_sun.r > dusk_sun.g and dusk_sun.g >= dusk_sun.b, "sunset light is warm and low", str(dusk_sun))

	clock.set_time(0.0)
	var night: Dictionary = clock.sample()
	_check(float(night["night"]) > 0.99, "midnight is fully dark", "%.2f" % float(night["night"]))
	_check(float(night["sun_energy"]) > 0.2, "moonlight keeps some directional light",
		"%.2f" % float(night["sun_energy"]))
	_check(float(night["ambient_energy"]) >= 0.4, "night ambient has a playable floor",
		"%.2f" % float(night["ambient_energy"]))
	_check(float(night["exposure"]) > float(noon["exposure"]), "night exposure is lifted",
		"%.2f vs %.2f" % [float(night["exposure"]), float(noon["exposure"])])
	var night_sun: Color = night["sun_color"]
	_check(night_sun.b > night_sun.r, "moonlight is cool, not orange", str(night_sun))
	var night_light := float(night["sun_energy"]) + float(night["ambient_energy"])
	_check(night_light >= 0.7, "night keeps a combined light budget the hunter can read in",
		"%.2f" % night_light)
	_check(float(night["fog_density"]) < 0.02, "night fog does not turn into a wall",
		"%.4f" % float(night["fog_density"]))


# ----------------------------------------------------------- day continuity ---
func _test_day_continuity() -> void:
	var clock = DayCycle.new()
	var steps := 720
	var previous: Dictionary = clock.sample()
	clock.set_time(0.0)
	previous = clock.sample()
	var max_sun_jump := 0.0
	var max_ambient_jump := 0.0
	var max_fog_jump := 0.0
	var min_sun := INF
	for i in range(steps):
		clock.set_time(float(i) / float(steps))
		var sample: Dictionary = clock.sample()
		max_sun_jump = maxf(max_sun_jump, absf(float(sample["sun_energy"]) - float(previous["sun_energy"])))
		max_ambient_jump = maxf(max_ambient_jump, absf(float(sample["ambient_energy"]) - float(previous["ambient_energy"])))
		var a: Color = sample["fog_color"]
		var b: Color = previous["fog_color"]
		max_fog_jump = maxf(max_fog_jump, absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b))
		min_sun = minf(min_sun, float(sample["sun_energy"]))
		previous = sample
	_check(max_sun_jump < 0.05, "sunlight changes smoothly through the whole day",
		"largest step %.3f" % max_sun_jump)
	_check(max_ambient_jump < 0.03, "ambient light changes smoothly", "largest step %.3f" % max_ambient_jump)
	_check(max_fog_jump < 0.03, "fog colour changes smoothly", "largest step %.3f" % max_fog_jump)
	_check(min_sun > 0.05, "there is never a frame with no light at all", "%.2f" % min_sun)


# ------------------------------------------------------------------- weather ---
func _test_weather() -> void:
	var wx = Weather.new(4242)
	_check(wx.label() == Weather.CLEAR, "weather starts clear")
	var clear: Dictionary = wx.sample()
	_check(absf(float(clear["fog"]) - 1.0) < 0.01, "clear weather keeps the baseline fog",
		"x%.2f" % float(clear["fog"]))
	_check(float(clear["rain"]) < 0.01, "clear weather has no rain")

	var sample_counts := {}
	var max_fog_jump := 0.0
	var max_sun_jump := 0.0
	var changes := 0
	var states_valid := true
	var raining_only_in_rain := true
	var previous: Dictionary = wx.sample()
	var elapsed := 0.0
	var first_change_at := -1.0
	while elapsed < 420.0:
		var started: bool = wx.update(DT)
		if started:
			changes += 1
			if first_change_at < 0.0:
				first_change_at = elapsed
		elapsed += DT
		var sample: Dictionary = wx.sample()
		sample_counts[sample["state"]] = true
		states_valid = states_valid and (sample["state"] in Weather.STATES)
		# Rain is allowed while fading out of the rain, but never in a settled
		# dry condition.
		if float(sample["rain"]) > 0.02 and sample["state"] != Weather.RAIN and float(sample["progress"]) >= 1.0:
			raining_only_in_rain = false
		max_fog_jump = maxf(max_fog_jump, absf(float(sample["fog"]) - float(previous["fog"])))
		max_sun_jump = maxf(max_sun_jump, absf(float(sample["sun"]) - float(previous["sun"])))
		previous = sample
	_check(changes >= 3, "weather changes over a long session", "%d changes in 7 min" % changes)
	_check(first_change_at >= Weather.HOLD_MIN * 0.9, "the first change waits for the hold time",
		"%.0f s" % first_change_at)
	_check(states_valid, "weather only ever reports known conditions")
	_check(raining_only_in_rain, "rain only falls while the condition is rain")
	_check(max_fog_jump < 0.02, "fog blends instead of snapping", "largest step %.4f" % max_fog_jump)
	_check(max_sun_jump < 0.02, "lighting blends instead of snapping", "largest step %.4f" % max_sun_jump)
	_check(sample_counts.size() >= 3, "a long session sees several conditions",
		", ".join(sample_counts.keys()))

	var rain = Weather.new(7)
	rain.force_state(Weather.RAIN)
	var heavy: Dictionary = rain.sample()
	_check(float(heavy["rain"]) > 0.99, "forced rain is full strength")
	_check(rain.is_storm(), "rain counts as a storm")
	_check(float(heavy["fog"]) > 1.5, "rain thickens the air", "x%.2f" % float(heavy["fog"]))
	_check(float(heavy["sun"]) < 0.6, "rain dims the sun", "x%.2f" % float(heavy["sun"]))
	_check(float(heavy["wind"]) > 1.0, "rain brings more wind", "x%.2f" % float(heavy["wind"]))

	var fog = Weather.new(7)
	fog.force_state(Weather.FOG)
	var thick: Dictionary = fog.sample()
	_check(float(thick["fog"]) > float(heavy["fog"]), "fog is thicker than rain",
		"x%.2f vs x%.2f" % [float(thick["fog"]), float(heavy["fog"])])
	_check(float(thick["rain"]) < 0.01, "fog brings no rain")
	_check(float(DayCycle.DAY_FOG_DENSITY) * float(thick["fog"]) < 0.05,
		"even thick fog leaves more than 20 m of visibility",
		"density %.4f" % (DayCycle.DAY_FOG_DENSITY * float(thick["fog"])))

	var mixed := [float(Weather.PROFILES["clear"]["fog"]), float(Weather.PROFILES["cloudy"]["fog"]), float(Weather.PROFILES["rain"]["fog"]), float(Weather.PROFILES["fog"]["fog"])]
	_check(mixed[0] < mixed[1] and mixed[1] < mixed[2] and mixed[2] < mixed[3],
		"conditions get progressively hazier", str(mixed))


func _test_weather_determinism() -> void:
	var a = Weather.new(2024)
	var b = Weather.new(2024)
	var c = Weather.new(2025)
	var a_states: Array[String] = []
	var b_states: Array[String] = []
	var c_states: Array[String] = []
	for i in range(int(240.0 / DT)):
		a.update(DT)
		b.update(DT)
		c.update(DT)
		if a_states.is_empty() or a_states[-1] != a.label():
			a_states.append(a.label())
		if b_states.is_empty() or b_states[-1] != b.label():
			b_states.append(b.label())
		if c_states.is_empty() or c_states[-1] != c.label():
			c_states.append(c.label())
	_check(a_states == b_states, "the same seed replays the same weather", str(a_states))
	_check(a_states != c_states, "a different seed changes the weather", str(c_states))
	_check(a_states.size() >= 2, "the seeded run actually changed weather", str(a_states))


# ------------------------------------------------------- wildlife modifiers ---
func _test_wildlife_modifiers() -> void:
	var world = LivingWorld.new()
	world.day = DayCycle.new()
	world.weather = Weather.new(11)

	world.day.set_time(0.5)
	world.weather.force_state(Weather.CLEAR)
	var clear: Dictionary = world._compute_modifiers(world.day.sample(), world.weather.sample())
	_check(absf(float(clear["vision"]) - 1.0) < 0.0001 and absf(float(clear["hearing"]) - 1.0) < 0.0001,
		"clear midday leaves wildlife senses untouched",
		"vision %.2f, hearing %.2f" % [float(clear["vision"]), float(clear["hearing"])])
	_check(absf(float(clear["memory"]) - 1.0) < 0.0001, "clear midday leaves threat memory untouched")

	world.day.set_time(0.0)
	var night: Dictionary = world._compute_modifiers(world.day.sample(), world.weather.sample())
	_check(float(night["vision"]) < 1.0, "deer see less at night", "vision x%.2f" % float(night["vision"]))
	_check(float(night["hearing"]) > 1.0, "deer hear better at night", "hearing x%.2f" % float(night["hearing"]))
	_check(float(night["memory"]) > 1.0, "a night scare is remembered longer", "memory x%.2f" % float(night["memory"]))

	world.day.set_time(0.5)
	world.weather.force_state(Weather.RAIN)
	var rain: Dictionary = world._compute_modifiers(world.day.sample(), world.weather.sample())
	_check(float(rain["hearing"]) < 1.0, "rain masks sound for the deer", "hearing x%.2f" % float(rain["hearing"]))
	_check(float(rain["memory"]) > 1.0, "a deer stays spooked longer in rain", "memory x%.2f" % float(rain["memory"]))

	var bounded := true
	for t in [0.0, 0.13, 0.25, 0.4, 0.5, 0.66, 0.75, 0.9]:
		for condition in [Weather.CLEAR, Weather.CLOUDY, Weather.RAIN, Weather.FOG]:
			world.day.set_time(t)
			world.weather.force_state(condition)
			var m: Dictionary = world._compute_modifiers(world.day.sample(), world.weather.sample())
			if float(m["vision"]) < 0.75 or float(m["hearing"]) < 0.7 or float(m["memory"]) > 1.35:
				bounded = false
	_check(bounded, "weather never pushes senses outside the fairness band")

	# The deer itself: a night-scaled profile still has sane, ordered thresholds.
	var ai = DeerAI.new(77)
	var base_vision: float = ai.profile.vision_range
	ai.set_environment_modifiers(0.88, 1.12, 1.1)
	_check(absf(ai.profile.vision_range - base_vision * 0.88) < 0.001,
		"the deer's profile applies the environment scale", "%.1f m" % ai.profile.vision_range)
	_check(ai.profile.confirm_distance < ai.profile.vision_range,
		"flight is still committed to before the edge of sight",
		"%.1f m vs %.1f m" % [ai.profile.confirm_distance, ai.profile.vision_range])
	ai.set_environment_modifiers(1.0, 1.0, 1.0)
	_check(absf(ai.profile.vision_range - base_vision) < 0.0001,
		"clearing the modifiers restores the tuned baseline", "%.1f m" % ai.profile.vision_range)

	# And the hunt still works at night.
	var sim := _simulate_night_chase(77)
	_check(sim["captured"] and sim["captured_at"] > 3.0 and sim["captured_at"] < 30.0,
		"a night-scaled deer is still catchable in a fair chase", "%.1f s" % sim["captured_at"])

	var calm = DeerAI.new(88)
	calm.set_facing(Vector3(0, 0, -1))
	calm.set_environment_modifiers(0.88, 1.12, 1.1)
	calm.update(DT, Vector3.ZERO, Vector3(0, 0.1, -12.0))
	_check(calm.state == DeerAI.GRAZING, "at night a hunter 12 m away is not spotted at once",
		"%s at %.1f m" % [calm.state, calm.perception.distance])
	var spotted = DeerAI.new(88)
	spotted.set_facing(Vector3(0, 0, -1))
	spotted.set_environment_modifiers(0.88, 1.12, 1.1)
	spotted.update(DT, Vector3.ZERO, Vector3(0, 0.1, -10.5))
	_check(spotted.state == DeerAI.ALERTED, "but inside the reduced night range the deer reacts",
		spotted.state)


func _simulate_night_chase(seed_value: int) -> Dictionary:
	var ai = DeerAI.new(seed_value)
	ai.set_environment_modifiers(0.88, 1.12, 1.1)
	var deer := Vector3(0, 0.1, 0)
	var hunter := Vector3(0, 0.1, -11.0)
	var t := 0.0
	var captured_at := -1.0
	while t < 40.0:
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


# ---------------------------------------------------------------- live scene ---
func _test_scene() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_main.set_physics_process(false)

	var world = _main.living_world
	_check(world != null and world.day != null and world.weather != null,
		"the scene builds a living world with a clock and weather")
	_check(world.day.time_of_day > 0.2 and world.day.time_of_day < 0.8,
		"the scene starts in daylight", world.day.clock_text())

	var rain: GPUParticles3D = world.rain_info["node"]
	_check(rain != null and rain.amount <= 800, "rain is one bounded particle system",
		"%d particles" % rain.amount)
	_check(not rain.emitting, "it does not rain in clear weather")
	_check(not rain.cast_shadow, "rain costs no shadow map")

	var forest_material = _main.forest_info["material"]
	_check(forest_material is ShaderMaterial, "trees use the wind shader")
	var shader_mat := forest_material as ShaderMaterial
	var strength: float = float(shader_mat.get_shader_parameter("wind_strength"))
	_check(strength > 0.0, "the trees have a non-zero wind strength", "%.3f m" % strength)
	_check(_main.forest_info["variant_count"] == 8, "all eight tree variants share that one material",
		"%d variants" % _main.forest_info["variant_count"])

	var tufts: MultiMeshInstance3D = _main.get_node_or_null("GrassTufts")
	_check(tufts != null, "the scene adds grass tufts")
	if tufts != null:
		_check(tufts.multimesh.instance_count >= 200, "grass is one instanced batch",
			"%d clumps" % tufts.multimesh.instance_count)
		_check(tufts.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"grass casts no shadows")
		_check(tufts.multimesh.mesh.surface_get_material(0) is ShaderMaterial,
			"grass sways from the same kind of shader")

	var shadow_lights := 0
	for child in _main.get_children():
		if child is DirectionalLight3D and (child as DirectionalLight3D).shadow_enabled:
			shadow_lights += 1
	_check(shadow_lights == 1, "the day cycle still uses a single shadow map", "%d light" % shadow_lights)

	var env: Environment = _main.environment_info["environment"]
	_check(env.fog_density > 0.004 and env.fog_density < 0.02,
		"starting daylight fog matches the approved look", "%.4f" % env.fog_density)
	_check(world.APPLY_INTERVAL >= 0.05, "environment updates are throttled, not per frame",
		"%.2f s" % world.APPLY_INTERVAL)

	_main.queue_free()
	await get_tree().process_frame


func _test_scene_night_and_rain() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_main.set_physics_process(false)

	var world = _main.living_world
	var env: Environment = _main.environment_info["environment"]
	var sun: DirectionalLight3D = _main.environment_info["sun"]
	var day_energy := sun.light_energy
	var day_fog := env.fog_density
	var day_hud: String = world.hud_text()

	world.day.set_time(0.0)
	world.weather.force_state(Weather.CLEAR)
	world.apply()
	_main._apply_wildlife_environment()
	_check(sun.light_energy < day_energy, "night dims the light", "%.2f -> %.2f" % [day_energy, sun.light_energy])
	_check(sun.light_energy > 0.1, "night light never reaches zero", "%.2f" % sun.light_energy)
	_check(env.fog_density > 0.0, "night fog still exists, so distance still fades")
	_check(world.hud_text() != day_hud, "the HUD clock reflects the new hour", world.hud_text())
	var night_senses: Dictionary = world.wildlife_modifiers()
	_check(float(night_senses["vision"]) < 1.0, "the deer senses are updated for night",
		"vision x%.2f" % float(night_senses["vision"]))
	var night_vision: float = _main.deer_ai.profile.vision_range
	_check(absf(night_vision - DeerAI.DETECT_RADIUS * float(night_senses["vision"])) < 0.01,
		"the live deer's sight matches the night scale", "%.2f m" % night_vision)

	world.day.set_time(0.5)
	world.weather.force_state(Weather.RAIN)
	world.apply()
	_main._apply_wildlife_environment()
	var rain: GPUParticles3D = world.rain_info["node"]
	_check(rain.emitting and rain.amount_ratio > 0.9, "rain falls in the rain",
		"ratio %.2f" % rain.amount_ratio)
	_check(env.fog_density > day_fog, "rain thickens the fog", "%.4f -> %.4f" % [day_fog, env.fog_density])
	_check(sun.light_energy < day_energy, "rain dims the sun", "%.2f" % sun.light_energy)

	var ground: StandardMaterial3D = _main.ground_info["material"]
	_check(ground.albedo_color.r < 0.99 and ground.roughness < 0.9,
		"the ground looks wet while it rains", "roughness %.2f" % ground.roughness)

	world.weather.force_state(Weather.CLEAR)
	world.apply()
	_check(absf(ground.roughness - 0.96) < 0.001 and ground.albedo_color.r > 0.99,
		"the ground dries when the rain stops", "roughness %.2f" % ground.roughness)

	# Back to clear midday: the deer must get its tuned senses back exactly.
	var clear_senses: Dictionary = world.wildlife_modifiers()
	_check(absf(float(clear_senses["vision"]) - 1.0) < 0.0001 and absf(float(clear_senses["hearing"]) - 1.0) < 0.0001,
		"clear midday restores the deer's tuned senses")

	_main.queue_free()
	await get_tree().process_frame

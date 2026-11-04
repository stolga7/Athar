extends RefCounted
## Binds time of day, weather and wind to the rendered world.
##
## The scene builds the environment, ground and rain once; this object owns the
## clock and the weather and pushes the current state into those pieces. Keeping
## it separate means the whole "living world" can be stepped and inspected in a
## headless test without a renderer, and `main.gd` stays about the hunter.
##
## Update cadence: the clock advances every frame, but the expensive part (sky
## colours, light energies, fog, rain, ground wetness, wildlife senses) is only
## re-applied every APPLY_INTERVAL seconds, which is far below what an eye can
## notice at these transition speeds and keeps per-frame cost predictable on a
## phone.

const DayCycle := preload("res://scripts/world/day_cycle.gd")
const Weather := preload("res://scripts/world/weather.gd")
const Rain := preload("res://scripts/world/rain.gd")

## Seconds between visual updates of the environment.
const APPLY_INTERVAL := 0.1

## Wildlife senses under weather and darkness. Clear midday is exactly 1.0, so
## the Phase 3.2 behaviour is untouched in clear weather.
const NIGHT_VISION := 0.12
const RAIN_VISION := 0.05
const FOG_VISION := 0.10
const MIN_VISION := 0.78
const NIGHT_HEARING := 0.15
const RAIN_HEARING := 0.28
const MIN_HEARING := 0.72
const NIGHT_MEMORY := 0.10
const RAIN_MEMORY := 0.15

var day: RefCounted
var weather: RefCounted
var rain_info := {}
var environment_info := {}
var ground_info := {}

var _apply_timer := 0.0
var _hunter_position := Vector3.ZERO
var _rain_intensity := 0.0
var _wind := 1.0
var _modifiers := {"vision": 1.0, "hearing": 1.0, "memory": 1.0}
var _phase := ""
var _weather_label := ""

## Per-region atmosphere. Multipliers rather than absolute colours, so the clock
## and the weather stay authoritative: a region tints noon and midnight, it does
## not replace them. The default is neutral, which is why the silver forest looks
## exactly as it did before regions existed.
const NEUTRAL_TINT := {
	"sun_color": Color(1, 1, 1),
	"sun_energy": 1.0,
	"ambient_color": Color(1, 1, 1),
	"fog_color": Color(1, 1, 1),
	"fog_density": 1.0,
	"sky_tint": Color(1, 1, 1),
	"sky_amount": 0.0,
	"exposure": 1.0,
}
var region_tint := NEUTRAL_TINT.duplicate()


func setup(env_info: Dictionary, ground: Dictionary, seed_value: int) -> void:
	environment_info = env_info
	ground_info = ground
	day = DayCycle.new()
	weather = Weather.new(seed_value)
	rain_info = Rain.build(environment_info["world_environment"].get_parent())
	apply()
	_last_seen_signature = signature()


var _last_seen_signature := ""


func update(delta: float, hunter_position: Vector3) -> void:
	_hunter_position = hunter_position
	day.advance(delta)
	weather.update(delta)
	_apply_timer -= delta
	if _apply_timer > 0.0:
		Rain.apply(rain_info, hunter_position, _rain_intensity, _wind)
		return
	_apply_timer = APPLY_INTERVAL
	apply()
	Rain.apply(rain_info, hunter_position, _rain_intensity, _wind)


## True when the phase or weather label changed since the last call, so the scene
## only pushes new senses to the wildlife when something actually changed.
func consume_change() -> bool:
	var now := signature()
	if now == _last_seen_signature:
		return false
	_last_seen_signature = now
	return true


func signature() -> String:
	return "%s|%s" % [day.phase(), weather.label()]


func environment_signature() -> String:
	return "%s|%s|%.2f" % [day.phase(), weather.label(), weather.progress]


## Pushes the current clock and weather into lights, sky, fog, rain and ground.
func apply() -> void:
	var day_sample: Dictionary = day.sample()
	var wx: Dictionary = weather.sample()
	_rain_intensity = float(wx["rain"])
	_wind = float(wx["wind"])
	_phase = str(day_sample["phase"])
	_weather_label = weather.label()
	_apply_environment(day_sample, wx)
	_apply_ground_wetness(_rain_intensity)
	_modifiers = _compute_modifiers(day_sample, wx)
	# Keep the emitter with the player even when nothing else is re-applied.
	Rain.apply(rain_info, _hunter_position, _rain_intensity, _wind)


## Installs a region's atmosphere (see region_definition.gd) and re-applies it.
func set_region_tint(tint: Dictionary) -> void:
	region_tint = NEUTRAL_TINT.duplicate()
	for key in tint.keys():
		if region_tint.has(key):
			region_tint[key] = tint[key]
	_apply_timer = 0.0
	apply()


func atmosphere() -> Dictionary:
	return region_tint.duplicate()


## Points the living world at a new region's ground so rain wetness and grass wind
## hit the materials that are actually on screen.
func rebind_ground(ground: Dictionary) -> void:
	ground_info = ground
	_apply_ground_wetness(_rain_intensity)


func _apply_environment(day_sample: Dictionary, wx: Dictionary) -> void:
	var env: Environment = environment_info["environment"]
	var sun: DirectionalLight3D = environment_info["sun"]
	var fill: DirectionalLight3D = environment_info["fill"]
	var sky_material: ProceduralSkyMaterial = environment_info["sky_material"]

	var sun_mult := float(wx["sun"])
	var fog_mult := float(wx["fog"])
	var cloud := clampf(1.0 - sun_mult, 0.0, 1.0)

	sun.rotation_degrees = day_sample["sun_rotation"]
	sun.light_color = day_sample["sun_color"]
	sun.light_energy = float(day_sample["sun_energy"]) * sun_mult
	fill.light_energy = float(day_sample["fill_energy"]) * lerpf(1.0, 0.8, cloud)

	env.ambient_light_color = day_sample["ambient_color"]
	env.ambient_light_energy = float(day_sample["ambient_energy"]) * float(wx["ambient"])
	env.fog_light_color = day_sample["fog_color"]
	env.fog_density = float(day_sample["fog_density"]) * fog_mult
	env.fog_sky_affect = clampf(float(wx["fog_sky"]), 0.0, 1.0)
	env.tonemap_exposure = float(day_sample["exposure"]) * float(region_tint["exposure"])

	# Overcast greys the sky without lighting it up.
	var grey := Color(0.30, 0.32, 0.34)
	var top: Color = day_sample["sky_top"]
	var horizon: Color = day_sample["sky_horizon"]
	sky_material.sky_top_color = top.lerp(grey * maxf(top.get_luminance(), 0.05) * 2.0, cloud * 0.5)
	sky_material.sky_horizon_color = horizon.lerp(grey * maxf(horizon.get_luminance(), 0.06) * 2.0, cloud * 0.45)

	# Region atmosphere: a tint over the clock, never a replacement for it. A
	# neutral tint leaves every value exactly as the day cycle computed it.
	sun.light_color = _tinted(sun.light_color, region_tint["sun_color"])
	sun.light_energy *= float(region_tint["sun_energy"])
	env.ambient_light_color = _tinted(env.ambient_light_color, region_tint["ambient_color"])
	env.fog_light_color = _tinted(env.fog_light_color, region_tint["fog_color"])
	env.fog_density *= float(region_tint["fog_density"])
	var sky_amount := clampf(float(region_tint["sky_amount"]), 0.0, 1.0)
	if sky_amount > 0.0:
		var tint: Color = region_tint["sky_tint"]
		sky_material.sky_top_color = sky_material.sky_top_color.lerp(
			tint * maxf(sky_material.sky_top_color.get_luminance(), 0.06) * 2.0, sky_amount)
		sky_material.sky_horizon_color = sky_material.sky_horizon_color.lerp(
			tint * maxf(sky_material.sky_horizon_color.get_luminance(), 0.06) * 2.0, sky_amount * 0.85)

	# Wind is a single shader parameter shared by every tree material and the grass.
	_wind_strength = float(wx["wind"])
	_apply_wind(environment_info, _wind_strength)
	if ground_info.has("tuft_material"):
		_set_wind(ground_info["tuft_material"], 0.075 * _wind_strength)


var _wind_strength := 1.0


## Multiplies a colour channel-wise; alpha is left alone.
static func _tinted(base: Color, factor: Color) -> Color:
	return Color(base.r * factor.r, base.g * factor.g, base.b * factor.b, base.a)


func _apply_wind(env_info: Dictionary, strength: float) -> void:
	if env_info.has("foliage_material") and env_info["foliage_material"] != null:
		_set_wind(env_info["foliage_material"], 0.14 * strength)


func _set_wind(material: Material, strength: float) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("wind_strength", strength)


## Wet ground: a touch darker and glossier while it rains, easing both ways with
## the same blend the rain uses, so no snap when a shower starts or stops.
func _apply_ground_wetness(intensity: float) -> void:
	var material: StandardMaterial3D = ground_info.get("material", null)
	if material == null:
		return
	material.albedo_color = Color(1, 1, 1).lerp(Color(0.78, 0.80, 0.82), intensity)
	material.roughness = lerpf(0.96, 0.74, intensity)


func _compute_modifiers(day_sample: Dictionary, wx: Dictionary) -> Dictionary:
	var night := float(day_sample["night"])
	var rain := float(wx["rain"])
	# Cloud/fog haze: 0 in clear weather, up to 1 in thick fog.
	var haze := clampf((float(wx["fog"]) - 1.0) / 2.4, 0.0, 1.0)
	var vision := clampf(1.0 - NIGHT_VISION * night - RAIN_VISION * rain - FOG_VISION * haze, MIN_VISION, 1.0)
	var hearing := clampf(1.0 + NIGHT_HEARING * night - RAIN_HEARING * rain, MIN_HEARING, 1.2)
	var memory := 1.0 + NIGHT_MEMORY * night + RAIN_MEMORY * rain
	return {"vision": vision, "hearing": hearing, "memory": memory}


## Senses multipliers for the wildlife layer, handed to the deer when they change.
func wildlife_modifiers() -> Dictionary:
	return _modifiers.duplicate()


## Short text for the HUD: the clock plus the weather.
func hud_text() -> String:
	return "%s  %s" % [day.clock_text(), _weather_label.to_upper()]


func phase_name() -> String:
	return _phase


func weather_label() -> String:
	return _weather_label

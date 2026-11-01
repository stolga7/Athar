extends RefCounted
## Time of day for the ATHAR wilderness.
##
## Pure logic, no scene nodes: it owns a clock and turns it into a set of lighting
## targets, so the maths can be tested without a renderer and the scene can apply
## the result once per frame.
##
## The day runs from midnight (0.0) through sunrise (0.25), noon (0.5), sunset
## (0.75) and back to midnight. Every value is a continuous function of the
## clock; nothing switches abruptly, so there is no visible pop at any hour.
##
## Noon reproduces the Phase 3.1 lighting exactly (sun 1.55 at -44 degrees,
## ambient 1.00, fog 0.0095), which keeps the existing visual tests meaningful
## and makes the daytime look the one the owner already approved.
##
## Night is deliberately playable rather than realistic: the sun light becomes a
## dim blue moon with shadows, ambient keeps a cool floor, and exposure is lifted
## slightly. The hunter and deer must still read at 02:00 on a phone.

## Real seconds for a full day. Short enough to see weather and light change in
## one session, long enough that midday does not flash past.
const SECONDS_PER_DAY := 480.0
## Start mid-morning: the approved Phase 3.1 look, with the whole day ahead.
const START_TIME := 0.5
## Noon sun elevation, matching the Phase 3.1 rotation of -44 degrees.
const MAX_SUN_ELEVATION := 44.0
## Moon elevation at night, high enough to keep shapes readable.
const MOON_ELEVATION := 38.0
## Sun azimuth sweeps east to west across the day.
const AZIMUTH_BASE := -40.0
const AZIMUTH_SWEEP := 300.0

const DAY_SUN_COLOR := Color(1.0, 0.92, 0.80)
const DUSK_SUN_COLOR := Color(1.0, 0.58, 0.32)
const MOON_COLOR := Color(0.62, 0.72, 0.98)

const DAY_SUN_ENERGY := 1.55
const MOON_ENERGY := 0.55
## Extra light while the sun is on the horizon, so dawn and dusk stay readable
## instead of turning the hunter into a silhouette.
const TWILIGHT_ENERGY := 0.80

const DAY_AMBIENT_COLOR := Color(0.34, 0.35, 0.375)
const DUSK_AMBIENT_COLOR := Color(0.46, 0.36, 0.35)
const NIGHT_AMBIENT_COLOR := Color(0.25, 0.30, 0.44)
const DAY_AMBIENT_ENERGY := 1.00
## Night floor: dark enough to read as night, bright enough to hunt in.
const NIGHT_AMBIENT_ENERGY := 0.92

const DAY_FOG_COLOR := Color(0.118, 0.138, 0.142)
const DUSK_FOG_COLOR := Color(0.165, 0.125, 0.108)
const NIGHT_FOG_COLOR := Color(0.048, 0.058, 0.092)
const DAY_FOG_DENSITY := 0.0095

const DAY_SKY_TOP := Color(0.042, 0.068, 0.088)
const DUSK_SKY_TOP := Color(0.075, 0.062, 0.105)
const NIGHT_SKY_TOP := Color(0.016, 0.022, 0.044)
const DAY_SKY_HORIZON := Color(0.150, 0.158, 0.155)
const DUSK_SKY_HORIZON := Color(0.290, 0.170, 0.130)
const NIGHT_SKY_HORIZON := Color(0.052, 0.062, 0.098)

const DAY_EXPOSURE := 1.45
const NIGHT_EXPOSURE := 1.72
const DAY_FILL := 0.30
const NIGHT_FILL := 0.22

## Phase boundaries in day fraction. Between them the look is interpolated, so
## the labels only affect text and gameplay, never a hard visual switch.
const PHASE_MIDNIGHT := 0.03
const PHASE_DAWN := 0.22
const PHASE_MORNING := 0.30
const PHASE_EVENING := 0.68
const PHASE_DUSK := 0.78
const PHASE_NIGHT := 0.86

var time_of_day := START_TIME


func _init(start_time := START_TIME) -> void:
	time_of_day = fposmod(start_time, 1.0)


func reset(start_time := START_TIME) -> void:
	time_of_day = fposmod(start_time, 1.0)


## Advances the clock. Returns true when the phase label changed.
func advance(delta: float) -> bool:
	var before := phase()
	time_of_day = fposmod(time_of_day + delta / SECONDS_PER_DAY, 1.0)
	return phase() != before


func set_time(value: float) -> void:
	time_of_day = fposmod(value, 1.0)


## Sun height in the sky: +1 at noon, 0 at sunrise/sunset, -1 at midnight.
func sun_height() -> float:
	return sin((time_of_day - 0.25) * TAU)


## 0 at night, 1 in full daylight, smooth through dawn and dusk.
func daylight() -> float:
	return clampf(sun_height() * 2.4, 0.0, 1.0)


## 0 during the day, 1 in full night.
func darkness() -> float:
	return clampf(-sun_height() * 2.4, 0.0, 1.0)


## 1 exactly at sunrise/sunset, 0 well above or below the horizon.
func twilight() -> float:
	return clampf(1.0 - absf(sun_height()) * 4.0, 0.0, 1.0)


## "night", "dawn", "day" or "dusk", used by the HUD and by wildlife caution.
func phase() -> String:
	if time_of_day < PHASE_DAWN or time_of_day >= PHASE_NIGHT:
		return "night"
	if time_of_day < PHASE_MORNING:
		return "dawn"
	if time_of_day < PHASE_EVENING:
		return "day"
	if time_of_day < PHASE_DUSK:
		return "dusk"
	return "night" if time_of_day >= PHASE_NIGHT else "dusk"


## Everything the renderer needs for this instant. All continuous in the clock.
func sample() -> Dictionary:
	var day := daylight()
	var night := darkness()
	var glow := twilight()
	# Weighting for warm dawn/dusk colour: strongest while the sun is low.
	var warm := glow
	var sun_rotation := Vector3(-MAX_SUN_ELEVATION * sun_height(), AZIMUTH_BASE + (time_of_day - 0.5) * AZIMUTH_SWEEP, 0.0)
	if sun_height() < 0.0:
		# Below the horizon the shadow light becomes the moon, fixed high.
		sun_rotation = Vector3(-MOON_ELEVATION, AZIMUTH_BASE + (0.5 - time_of_day) * AZIMUTH_SWEEP, 0.0)

	var sun_color := DAY_SUN_COLOR.lerp(DUSK_SUN_COLOR, warm * 0.75).lerp(MOON_COLOR, night)
	var sun_energy := DAY_SUN_ENERGY * day + MOON_ENERGY * night + TWILIGHT_ENERGY * warm * (1.0 - night)
	var ambient_color := DAY_AMBIENT_COLOR.lerp(DUSK_AMBIENT_COLOR, warm).lerp(NIGHT_AMBIENT_COLOR, night)
	var ambient_energy := lerpf(DAY_AMBIENT_ENERGY, NIGHT_AMBIENT_ENERGY, night)
	var fog_color := DAY_FOG_COLOR.lerp(DUSK_FOG_COLOR, warm).lerp(NIGHT_FOG_COLOR, night)
	var sky_top := DAY_SKY_TOP.lerp(DUSK_SKY_TOP, warm).lerp(NIGHT_SKY_TOP, night)
	var sky_horizon := DAY_SKY_HORIZON.lerp(DUSK_SKY_HORIZON, warm).lerp(NIGHT_SKY_HORIZON, night)

	return {
		"time": time_of_day,
		"phase": phase(),
		"daylight": day,
		"night": night,
		"twilight": glow,
		"sun_rotation": sun_rotation,
		"sun_color": sun_color,
		"sun_energy": maxf(0.05, sun_energy),
		"ambient_color": ambient_color,
		"ambient_energy": ambient_energy,
		"fill_energy": lerpf(DAY_FILL, NIGHT_FILL, night),
		"fog_color": fog_color,
		"fog_density": DAY_FOG_DENSITY,
		"sky_top": sky_top,
		"sky_horizon": sky_horizon,
		"exposure": lerpf(DAY_EXPOSURE, NIGHT_EXPOSURE, night),
	}


## "06:41"-style clock for the HUD, purely for the player.
func clock_text() -> String:
	var minutes := int(time_of_day * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]

extends RefCounted
## Weather for the ATHAR wilderness: clear, cloudy, rain and fog.
##
## Pure logic and no nodes, like the day cycle: it owns a small state machine and
## hands the scene a set of multipliers to blend into the lighting, the fog and
## the rain particles.
##
## Transitions are eased over TRANSITION_SECONDS instead of snapping, so weather
## rolls in. Each condition holds for a while before the next one is chosen, and
## the choice comes from an injected generator, so a seeded run replays the same
## weather while normal play stays unpredictable.
##
## Rain and fog are tuned for play, not realism: even at full strength the fog
## stays well short of hiding the deer's 13 m detection ring, and rain slows the
## deer's hearing rather than blinding anybody (see `caution_scale`).

const CLEAR := "clear"
const CLOUDY := "cloudy"
const RAIN := "rain"
const FOG := "fog"
const STATES := [CLEAR, CLOUDY, RAIN, FOG]

## Seconds to blend from one condition to another.
const TRANSITION_SECONDS := 14.0
## How long a condition lasts once fully arrived.
const HOLD_MIN := 38.0
const HOLD_MAX := 85.0

## Multipliers applied on top of the day cycle. `fog` scales fog density, `sun`
## and `ambient` scale light energy, `rain` drives the particle emitter, `wind`
## feeds the vegetation shader, `fog_sky` is how much fog tints the sky.
const PROFILES := {
	"clear": {"fog": 1.00, "sun": 1.00, "ambient": 1.00, "rain": 0.0, "wind": 0.55, "fog_sky": 0.85},
	"cloudy": {"fog": 1.45, "sun": 0.68, "ambient": 1.06, "rain": 0.0, "wind": 0.85, "fog_sky": 0.95},
	"rain": {"fog": 2.05, "sun": 0.50, "ambient": 1.15, "rain": 1.0, "wind": 1.25, "fog_sky": 1.00},
	"fog": {"fog": 3.40, "sun": 0.58, "ambient": 1.10, "rain": 0.0, "wind": 0.45, "fog_sky": 1.00},
}

## Where the weather may go next, with weights. Rain and fog always pass through
## cloud, so the sky never jumps from downpour to clear.
const NEXT_STATES := {
	"clear": {"clear": 0.55, "cloudy": 0.45},
	"cloudy": {"clear": 0.28, "cloudy": 0.10, "rain": 0.40, "fog": 0.22},
	"rain": {"cloudy": 0.65, "rain": 0.20, "fog": 0.15},
	"fog": {"cloudy": 0.60, "fog": 0.25, "clear": 0.15},
}

var state := CLEAR
var target_state := CLEAR
## 0 while starting a transition, 1 once the target condition has arrived.
var progress := 1.0
var hold_timer := 0.0

var _from := {}
var _to := {}
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = -1) -> void:
	if seed_value < 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	_from = _profile(CLEAR).duplicate()
	_to = _profile(CLEAR).duplicate()
	hold_timer = _next_hold()


## Current blended condition, for the tests and the HUD.
func sample() -> Dictionary:
	var smooth := _ease(progress)
	var out := {}
	var keys: Array = _to.keys()
	for key in keys:
		out[key] = lerpf(float(_from.get(key, 0.0)), float(_to.get(key, 0.0)), smooth)
	out["state"] = target_state
	out["progress"] = progress
	out["raining"] = float(out.get("rain", 0.0))
	return out


## True while the weather is actually falling (used for wildlife caution).
func is_storm() -> bool:
	return target_state == RAIN and progress > 0.5


func label() -> String:
	return target_state


## Advances the weather. Returns true when a new condition began this step.
func update(delta: float) -> bool:
	var started := false
	if progress < 1.0:
		progress = minf(1.0, progress + delta / TRANSITION_SECONDS)
		if progress >= 1.0:
			state = target_state
	else:
		hold_timer -= delta
		if hold_timer <= 0.0:
			_begin(_pick_next())
			started = true
	return started


## Jumps straight to a condition, e.g. for a screenshot. Tests use it too.
func force_state(next_state: String, instant := true) -> void:
	if not PROFILES.has(next_state):
		return
	_begin(next_state)
	if instant:
		progress = 1.0
		state = next_state
		_from = _profile(next_state).duplicate()
		_to = _profile(next_state).duplicate()


func _begin(next_state: String) -> void:
	_from = sample().duplicate()
	_from.erase("state")
	_from.erase("progress")
	_from.erase("raining")
	target_state = next_state
	_to = _profile(next_state).duplicate()
	progress = 0.0
	hold_timer = _next_hold()


func _pick_next() -> String:
	var table: Dictionary = NEXT_STATES[target_state]
	var roll := _rng.randf()
	var total := 0.0
	for key in table.keys():
		total += float(table[key])
	var cursor := 0.0
	for key in table.keys():
		cursor += float(table[key]) / total
		if roll <= cursor:
			return key
	return target_state


func _next_hold() -> float:
	return _rng.randf_range(HOLD_MIN, HOLD_MAX)


func _profile(name: String) -> Dictionary:
	return PROFILES[name].duplicate()


## Smoothstep, so a change of weather eases in and out instead of starting and
## stopping abruptly.
func _ease(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

extends RefCounted
## Vision, hearing and threat memory for a wildlife agent.
##
## Pure logic: positions in, a small snapshot of what the animal perceives out.
## The caller supplies a line-of-sight probe (a Callable that answers "is this
## path blocked?"), so the same code runs in the scene against real physics and
## in headless tests against a fake wall.
##
## Rules, in the order they are applied:
##   * Sight needs distance <= vision_range, an angle inside the field of view
##     (or a threat closer than proximity_range), and an unblocked line of sight.
##   * Hearing needs a moving threat: a sprinting hunter carries further than a
##     walking one, and a standing hunter is silent.
##   * Anything seen or heard is remembered for memory_time seconds, so an animal
##     does not relax the instant the threat disappears behind a trunk.

## Target speed at which the noise level is considered a full sprint.
const NOISE_REFERENCE_SPEED := 4.4
## Below this the animal treats the target as standing still.
const MIN_NOISE_SPEED := 0.3
## Target speed jumps above this are treated as a teleport, not a footstep.
const TELEPORT_SPEED := 9.0
## How quickly the speed estimate follows the target.
const SPEED_SMOOTHING := 8.0

var profile: RefCounted

## This frame's snapshot.
var distance := INF
var angle_degrees := 180.0
var visible_now := false
var heard_now := false
var noise_level := 0.0
var audible_range := 0.0
var target_speed := 0.0

## Threat memory.
var threat_position := Vector3.ZERO
var threat_known := false
var threat_seen := false
var confidence := 0.0
var memory_left := 0.0

var _last_target := Vector3.ZERO
var _has_last := false


func setup(anim_profile: RefCounted) -> void:
	profile = anim_profile


func reset() -> void:
	visible_now = false
	heard_now = false
	noise_level = 0.0
	audible_range = 0.0
	target_speed = 0.0
	threat_position = Vector3.ZERO
	threat_known = false
	threat_seen = false
	confidence = 0.0
	memory_left = 0.0
	_last_target = Vector3.ZERO
	_has_last = false


## Call once per simulation step. `facing` is the animal's look direction,
## `los_probe` is an optional Callable(from, to) -> bool that returns true when
## the straight path is blocked.
func update(delta: float, self_pos: Vector3, facing: Vector3, target_pos: Vector3, los_probe := Callable()) -> void:
	distance = _planar(self_pos, target_pos)
	_update_speed_estimate(delta, target_pos)
	noise_level = clampf(target_speed / NOISE_REFERENCE_SPEED, 0.0, 1.0)
	audible_range = profile.hearing_range * pow(noise_level, 0.7)
	heard_now = target_speed >= MIN_NOISE_SPEED and distance <= audible_range

	angle_degrees = _angle_to(facing, target_pos - self_pos)
	var in_view: bool = angle_degrees <= float(profile.vision_angle) * 0.5
	var close_by: bool = distance <= float(profile.proximity_range)
	visible_now = distance <= float(profile.vision_range) and (in_view or close_by) and not _blocked(self_pos, target_pos, los_probe)

	if visible_now:
		memory_left = profile.memory_time
		threat_position = target_pos
		confidence = 1.0
	elif heard_now:
		# Sound gives a direction, not a clean sighting: the animal remembers it
		# for less time than something it actually saw.
		memory_left = maxf(memory_left, profile.memory_time * 0.6)
		threat_position = target_pos
		confidence = maxf(confidence, 0.55)
	else:
		memory_left = maxf(0.0, memory_left - delta)
		confidence = maxf(0.0, confidence - delta * 1.5)

	threat_seen = visible_now
	threat_known = memory_left > 0.0


## True when a threat of this noise level would carry `range` metres.
func hears_noise(noise: float, at_range: float) -> bool:
	var reach: float = profile.hearing_range * pow(clampf(noise, 0.0, 1.0), 0.7)
	return at_range <= reach and noise * NOISE_REFERENCE_SPEED >= MIN_NOISE_SPEED


func _update_speed_estimate(delta: float, target_pos: Vector3) -> void:
	if not _has_last:
		_last_target = target_pos
		_has_last = true
		target_speed = 0.0
		return
	var moved := _planar(_last_target, target_pos)
	_last_target = target_pos
	if delta <= 0.0:
		return
	var instant := moved / delta
	if instant > TELEPORT_SPEED:
		# A new hunt, a jump cut or a stutter: not a footstep.
		target_speed = 0.0
		return
	target_speed = lerpf(target_speed, instant, clampf(delta * SPEED_SMOOTHING, 0.0, 1.0))


func _blocked(from: Vector3, to: Vector3, probe: Callable) -> bool:
	if not probe.is_valid():
		return false
	return bool(probe.call(from, to))


func _angle_to(facing: Vector3, offset: Vector3) -> float:
	var f := Vector3(facing.x, 0.0, facing.z)
	var o := Vector3(offset.x, 0.0, offset.z)
	if f.length_squared() < 0.000001 or o.length_squared() < 0.000001:
		return 0.0
	return rad_to_deg(acos(clampf(f.normalized().dot(o.normalized()), -1.0, 1.0)))


func _planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

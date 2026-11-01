extends RefCounted
## Heading smoothing and obstacle avoidance for a ground animal.
##
## The agent asks for one of these and gets back a direction it can move in
## without walking into a trunk:
##   turn()  eases the animal's facing toward its intended course, so it banks
##           instead of flipping 180 degrees in a frame.
##   avoid() samples a fan of headings around the intended course and returns
##           the closest one that is not blocked, remembering which side it
##           chose so it does not weave left and right every frame.
##
## "Blocked" comes from a Callable the caller supplies, so the scene uses real
## physics rays while tests use a fake wall. No allocation per frame beyond a
## few Vector3s.

## Candidate deviations from the intended course, in degrees.
const AVOID_ANGLES := [30.0, -30.0, 60.0, -60.0, 90.0, -90.0]

var heading := Vector3(0.0, 0.0, -1.0)

var _avoid_dir := Vector3.ZERO
var _avoid_timer := 0.0
## -1 keeps left, +1 keeps right, 0 undecided. Hysteresis against weaving.
var _avoid_side := 0


func reset(facing := Vector3(0.0, 0.0, -1.0)) -> void:
	heading = _normalized(facing, Vector3(0.0, 0.0, -1.0))
	_avoid_dir = Vector3.ZERO
	_avoid_timer = 0.0
	_avoid_side = 0


## Eases `heading` toward `desired`. Returns the new heading.
func turn(delta: float, desired: Vector3, turn_rate: float) -> Vector3:
	var target := _normalized(desired, Vector3.ZERO)
	if target == Vector3.ZERO:
		return heading
	var step := clampf(turn_rate * delta, 0.0, 1.0)
	heading = _normalized(heading.lerp(target, step), target)
	return heading


## Returns `desired` for a motion step of `lookahead` metres, rotated aside when
## something is in the way. `refresh` is how long a chosen detour is kept.
func avoid(from: Vector3, desired: Vector3, delta: float, lookahead: float, refresh: float, probe: Callable) -> Vector3:
	var course := _normalized(desired, Vector3.ZERO)
	if course == Vector3.ZERO or not probe.is_valid() or lookahead <= 0.0:
		_avoid_dir = Vector3.ZERO
		_avoid_timer = 0.0
		return course

	if _avoid_timer > 0.0 and _avoid_dir != Vector3.ZERO:
		# Keep the detour as long as it still leads somewhere open.
		if not _is_blocked(from, _avoid_dir, lookahead * 0.8, probe):
			_avoid_timer -= delta
			return _avoid_dir
		_avoid_timer = 0.0

	if not _is_blocked(from, course, lookahead, probe):
		_avoid_dir = Vector3.ZERO
		return course

	var best := Vector3.ZERO
	for angle in _fan():
		var candidate := _rotate(course, deg_to_rad(angle))
		if not _is_blocked(from, candidate, lookahead, probe):
			best = candidate
			_avoid_side = 1 if angle > 0.0 else -1
			break
	if best == Vector3.ZERO:
		# Boxed in on every sampled heading: take the least-bad side and let the
		# next probe look again rather than standing still.
		best = _rotate(course, deg_to_rad(90.0 * (1.0 if _avoid_side >= 0 else -1.0)))
		_avoid_side = 1 if _avoid_side >= 0 else -1
	_avoid_dir = best
	_avoid_timer = refresh
	return best


## Heading order prefers the side already chosen, so the animal commits to one
## way round an obstacle instead of oscillating around it.
func _fan() -> Array:
	if _avoid_side > 0:
		return [30.0, 60.0, 90.0, -30.0, -60.0, -90.0]
	if _avoid_side < 0:
		return [-30.0, -60.0, -90.0, 30.0, 60.0, 90.0]
	return AVOID_ANGLES


func is_clear(from: Vector3, direction: Vector3, lookahead: float, probe: Callable) -> bool:
	var course := _normalized(direction, Vector3.ZERO)
	if course == Vector3.ZERO or not probe.is_valid():
		return true
	return not _is_blocked(from, course, lookahead, probe)


func _is_blocked(from: Vector3, direction: Vector3, lookahead: float, probe: Callable) -> bool:
	return bool(probe.call(from, from + direction * lookahead))


func facing_side() -> int:
	return _avoid_side


func _rotate(v: Vector3, angle: float) -> Vector3:
	var c := cos(angle)
	var s := sin(angle)
	return Vector3(v.x * c - v.z * s, 0.0, v.x * s + v.z * c)


func _normalized(v: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	if flat.length_squared() < 0.000001:
		return fallback
	return flat.normalized()

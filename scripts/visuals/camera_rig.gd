extends Node3D
## ATHAR third-person camera with player look, zoom, collision and lock-on.
##
## Why this exists: the prototype camera was a fixed offset solved with
## look_at(), so any tree between the hunter and the camera filled the screen
## and the player could not look around at all. This rig adds:
##
##   1. a shorter, lower mobile framing (close enough to read the hunter),
##   2. exponential smoothing on the follow point and the yaw,
##   3. obstruction handling: a swept sphere is cast from the focus point to the
##      ideal camera position and the camera pulls in to the first thing it
##      would pass through (layers 1 and 2: ground and trunks),
##   4. player look: the right-hand touch area and the mouse drag feed
##      `add_look()`, and the yaw/pitch offsets are added on top of the hunter's
##      facing, so the camera can orbit without turning the hunter,
##   5. pinch/key zoom between 3.2 m and 9 m, and
##   6. a lock-on mode that frames the hunter and the target together.
##
## Pure presentation: it reads positions, never writes gameplay state, and uses
## no random numbers.

## Ideal distance from the focus point at the neutral zoom. At 6 m with a 60
## degree field of view the 1.8 m hunter fills about a third of the height.
const DISTANCE := 6.0
const ZOOM_MIN := 3.2
const ZOOM_MAX := 9.0
const PITCH_DEGREES := -14.0
## Where the camera looks: chest height, so the hunter sits in the lower middle.
const FOCUS_HEIGHT := 1.30
const FIELD_OF_VIEW := 60.0
const MIN_DISTANCE := 1.2
## Lateral offset towards the hunter's right shoulder, which keeps a deer ahead
## of him from hiding behind his own model.
const SHOULDER_OFFSET := 0.62
const CLOSE_PITCH_LIFT := 30.0
const CLOSE_RANGE := 3.4
const FOLLOW_RATE := 9.0
const YAW_RATE := 5.0
const PULL_OUT_RATE := 3.0
const PROBE_RADIUS := 0.32
const OBSTRUCTION_MASK := 1 | 2
const GROUND_CLEARANCE := 0.65

## Look limits, in radians. Pitch is relative to PITCH_DEGREES.
const MAX_YAW_OFFSET := 2.4
const MIN_PITCH_OFFSET := -0.55
const MAX_PITCH_OFFSET := 0.65
## How quickly a lock-on yaw takes over, per second.
const LOCK_RATE := 7.0
## Distance is pulled in this much while locked on, so the target fits.
const LOCK_ZOOM := 0.78

var camera: Camera3D
var focus := Vector3.ZERO
var yaw := 0.0
## Player look offsets, added on top of the hunter's facing.
var yaw_offset := 0.0
var pitch_offset := 0.0
## Look sensitivity multiplier from the settings screen.
var look_sensitivity := 1.0
## Requested distance multiplier (1.0 = DISTANCE).
var zoom := 1.0
var distance := DISTANCE
var clear_distance := DISTANCE
var obstructed := false
var locked_target: Node3D
var locked := false

var _probe_shape: SphereShape3D
var _excluded: Array[RID] = []


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "GameCamera"
	camera.fov = FIELD_OF_VIEW
	camera.near = 0.08
	camera.current = true
	add_child(camera)
	_probe_shape = SphereShape3D.new()
	_probe_shape.radius = PROBE_RADIUS


func ignore_bodies(rids: Array[RID]) -> void:
	_excluded = rids.duplicate()


func snap_to(target_position: Vector3, target_yaw: float) -> void:
	focus = target_position + Vector3(0, FOCUS_HEIGHT, 0)
	yaw = target_yaw + yaw_offset
	distance = _ideal_distance()
	clear_distance = distance
	obstructed = false
	_place(_basis(), 1.0)


## Player look, in pixels of drag (or radians, scaled by the caller).
func add_look(delta_pixels: Vector2) -> void:
	yaw_offset = clampf(yaw_offset - delta_pixels.x * 0.0042 * look_sensitivity, -MAX_YAW_OFFSET, MAX_YAW_OFFSET)
	pitch_offset = clampf(pitch_offset - delta_pixels.y * 0.0028 * look_sensitivity, MIN_PITCH_OFFSET, MAX_PITCH_OFFSET)


func set_look_sensitivity(value: float) -> void:
	look_sensitivity = clampf(value, 0.3, 2.5)


## Zoom in (positive) or out (negative), 0..1 scale steps.
func zoom_by(step: float) -> void:
	zoom = clampf(zoom + step, ZOOM_MIN / DISTANCE, ZOOM_MAX / DISTANCE)


func set_zoom(value: float) -> void:
	zoom = clampf(value, ZOOM_MIN / DISTANCE, ZOOM_MAX / DISTANCE)


func current_distance() -> float:
	return distance


func lock_on(target: Node3D) -> void:
	locked_target = target
	locked = target != null


func clear_lock() -> void:
	locked_target = null
	locked = false


func has_lock() -> bool:
	return locked and is_instance_valid(locked_target)


## Called once per physics frame by main.gd.
func update_camera(delta: float, target_position: Vector3, target_yaw: float) -> void:
	var ideal := target_yaw + yaw_offset
	if has_lock():
		var to_target: Vector3 = locked_target.global_position - target_position
		if Vector2(to_target.x, to_target.z).length() > 0.01:
			var lock_yaw := atan2(-to_target.x, -to_target.z)
			ideal = lerp_angle(ideal, lock_yaw, minf(1.0, delta * LOCK_RATE))
	var close := clampf((CLOSE_RANGE - distance) / (CLOSE_RANGE - MIN_DISTANCE), 0.0, 1.0)
	var focus_target := target_position + Vector3(0, FOCUS_HEIGHT + close * 0.65, 0)
	if has_lock():
		focus_target = focus_target.lerp(locked_target.global_position.lerp(focus_target, 0.35), 0.35)
	focus = focus.lerp(focus_target, _smooth(delta, FOLLOW_RATE))
	yaw = lerp_angle(yaw, ideal, _smooth(delta, YAW_RATE))

	var basis := _basis(close)
	var offset := _offset(basis)
	var full_length := offset.length()
	var allowed := minf(_clear_distance(focus, offset), full_length)
	clear_distance = allowed / maxf(full_length, 0.001) * _ideal_distance()
	obstructed = clear_distance < _ideal_distance() - 0.01
	var limit := maxf(clear_distance, MIN_DISTANCE)
	if limit < distance:
		distance = limit
	else:
		distance = lerpf(distance, limit, _smooth(delta, PULL_OUT_RATE))
	distance = clampf(distance, MIN_DISTANCE, _ideal_distance())
	_place(basis, distance / _ideal_distance())


func focus_point() -> Vector3:
	return focus


func _ideal_distance() -> float:
	var value := DISTANCE * zoom
	if has_lock():
		value *= LOCK_ZOOM
	return clampf(value, MIN_DISTANCE, ZOOM_MAX)


func _basis(close := 0.0) -> Basis:
	var pitch := deg_to_rad(PITCH_DEGREES - close * CLOSE_PITCH_LIFT) + pitch_offset
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)


func _offset(basis: Basis) -> Vector3:
	return basis * Vector3(0, 0, _ideal_distance()) + basis * Vector3(SHOULDER_OFFSET, 0, 0)


func _place(basis: Basis, scale: float) -> void:
	if camera == null:
		return
	var offset := _offset(basis) * clampf(scale, 0.0, 1.0)
	var position := focus + offset
	position.y = maxf(position.y, GROUND_CLEARANCE)
	camera.global_position = position
	var aim := focus + basis * Vector3(SHOULDER_OFFSET * 0.45, 0, 0)
	camera.look_at(aim, Vector3.UP)


func _clear_distance(from: Vector3, offset: Vector3) -> float:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return offset.length()
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _probe_shape
	params.transform = Transform3D(Basis(), from)
	params.motion = offset
	params.collision_mask = OBSTRUCTION_MASK
	params.collide_with_areas = false
	params.exclude = _excluded
	var hit: PackedFloat32Array = space.cast_motion(params)
	if hit.size() < 2:
		return offset.length()
	return clampf(hit[0] * offset.length(), 0.0, offset.length())


func _smooth(delta: float, rate: float) -> float:
	return 1.0 - exp(-rate * delta)

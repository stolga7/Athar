extends Node3D
## ATHAR third-person follow camera.
##
## Why this exists: the prototype camera was a fixed offset solved with
## look_at(), so any tree standing between the hunter and the camera filled the
## screen with canopy. This rig adds three things:
##
##   1. a shorter, lower mobile framing (close enough to read the hunter rig),
##   2. exponential smoothing on both the focus point and the yaw, so the view
##      glides instead of copying every little position change,
##   3. obstruction handling: a swept sphere is cast from the focus point out to
##      the ideal camera position, and the camera is pulled in to the first
##      thing it would pass through.
##
## The obstruction query uses collision layer 2 (tree trunks) and layer 1
## (ground). Trees only answer on layer 2, so pulling the camera in never
## changes hunter or deer movement.
##
## Pure presentation: it reads positions, never writes gameplay state, and uses
## no random numbers.

## Ideal distance from the focus point, chosen for a phone screen: at 6 m with a
## 60 degree field of view the 1.9 m hunter fills roughly a third of the height.
const DISTANCE := 6.0
const PITCH_DEGREES := -14.0
## Where the camera looks: chest height, so the hunter sits in the lower middle.
const FOCUS_HEIGHT := 1.35
const FIELD_OF_VIEW := 60.0
## Absolute floor, used only when the hunter is boxed in from every side. The
## camera still respects the obstruction distance above this value, so it never
## pushes back into the trunk it just stopped at.
const MIN_DISTANCE := 1.2
## Lateral offset towards the hunter's right shoulder. This keeps the hunter out
## of the middle of the screen, so a deer standing directly ahead is not hidden
## behind his own model, and it is what makes the close-in shots readable.
const SHOULDER_OFFSET := 0.62
## How much the camera looks further at close range, so a camera pinned to a
## trunk looks down over the hunter instead of filling the frame with his cloak.
const CLOSE_PITCH_LIFT := 30.0
const CLOSE_RANGE := 3.4
## Exponential smoothing rates (per second).
const FOLLOW_RATE := 9.0
const YAW_RATE := 5.0
## How fast the camera drifts back out once the obstruction clears. Slower than
## the pull-in on purpose: coming back out should never feel like a lurch.
const PULL_OUT_RATE := 3.0
## Radius of the swept sphere. Bigger than a pixel-width margin, small enough to
## fit between close trunks.
const PROBE_RADIUS := 0.32
const OBSTRUCTION_MASK := 1 | 2
## The camera never goes below this height, so it cannot end up under the ground
## plane even if the focus point dips.
const GROUND_CLEARANCE := 0.65

var camera: Camera3D
## Current (smoothed) focus point in world space.
var focus := Vector3.ZERO
var yaw := 0.0
## Smoothed, obstruction-clamped distance from the focus point.
var distance := DISTANCE
## Distance the last obstruction query allowed; DISTANCE when nothing is in the way.
var clear_distance := DISTANCE
## True while something is between the hunter and the ideal camera position.
var obstructed := false

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


## Physics bodies the camera is allowed to pass through (the hunter, the deer).
func ignore_bodies(rids: Array[RID]) -> void:
	_excluded = rids.duplicate()


## Places the camera immediately, without smoothing. Used on startup and after
## a teleport, where gliding in from the old position would look wrong.
func snap_to(target_position: Vector3, target_yaw: float) -> void:
	focus = target_position + Vector3(0, FOCUS_HEIGHT, 0)
	yaw = target_yaw
	distance = DISTANCE
	clear_distance = DISTANCE
	obstructed = false
	_place(_basis(), 1.0)


## Called once per physics frame by main.gd.
func update_camera(delta: float, target_position: Vector3, target_yaw: float) -> void:
	var close := clampf((CLOSE_RANGE - distance) / (CLOSE_RANGE - MIN_DISTANCE), 0.0, 1.0)
	var focus_target := target_position + Vector3(0, FOCUS_HEIGHT + close * 0.65, 0)
	focus = focus.lerp(focus_target, _smooth(delta, FOLLOW_RATE))
	yaw = lerp_angle(yaw, target_yaw, _smooth(delta, YAW_RATE))

	var basis := _basis(close)
	var offset := _offset(basis)
	var full_length := offset.length()
	var allowed := minf(_clear_distance(focus, offset), full_length)
	clear_distance = allowed / maxf(full_length, 0.001) * DISTANCE
	obstructed = clear_distance < DISTANCE - 0.01
	var limit := maxf(clear_distance, MIN_DISTANCE)
	if limit < distance:
		# Pull in at once: a frame of clipping through bark looks worse than a
		# sudden change of distance, and the probe already keeps a margin.
		distance = limit
	else:
		distance = lerpf(distance, limit, _smooth(delta, PULL_OUT_RATE))
	distance = clampf(distance, MIN_DISTANCE, DISTANCE)
	_place(basis, distance / DISTANCE)


## World position the camera is currently looking at.
func focus_point() -> Vector3:
	return focus


func _basis(close := 0.0) -> Basis:
	var pitch := deg_to_rad(PITCH_DEGREES - close * CLOSE_PITCH_LIFT)
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)


## The full unmounted camera offset from the focus point: back, up and to the
## hunter's right shoulder.
func _offset(basis: Basis) -> Vector3:
	return basis * Vector3(0, 0, DISTANCE) + basis * Vector3(SHOULDER_OFFSET, 0, 0)


func _place(basis: Basis, scale: float) -> void:
	if camera == null:
		return
	var offset := _offset(basis) * clampf(scale, 0.0, 1.0)
	var position := focus + offset
	position.y = maxf(position.y, GROUND_CLEARANCE)
	camera.global_position = position
	# Aim a little to the right of the focus as well, so the hunter sits left of
	# centre and the crosshair-height band of the screen stays clear.
	var aim := focus + basis * Vector3(SHOULDER_OFFSET * 0.45, 0, 0)
	camera.look_at(aim, Vector3.UP)


## Sweeps a small sphere from the focus point towards the ideal camera position
## and returns how far along `offset` it can travel before touching the world.
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
	# hit[0] is the fraction of the motion that is safe. Keeping the probe radius
	# as slack means the camera stops just short of the trunk.
	return clampf(hit[0] * offset.length(), 0.0, offset.length())


func _smooth(delta: float, rate: float) -> float:
	return 1.0 - exp(-rate * delta)

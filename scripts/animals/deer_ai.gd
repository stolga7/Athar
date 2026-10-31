extends RefCounted
## Deer behaviour for ATHAR: detection, alarm, flight and escape.
##
## Deliberately free of scene nodes and physics so it can be simulated in
## headless tests and replayed deterministically: update() is given a delta, the
## deer's position and the hunter's position, and returns the desired planar
## velocity. scripts/main.gd applies that velocity to the CharacterBody3D.
##
## State flow:
##   GRAZING  --hunter enters DETECT_RADIUS-->  ALERTED
##   ALERTED  --ALERT_DURATION elapses-->      FLEEING
##   FLEEING  --sprint stamina falls to SPRINT_EXIT_STAMINA-->  ESCAPING
##   ESCAPING --hunter closes inside SECOND_WIND_DISTANCE with stamina-->  FLEEING
##   ESCAPING --deer opens ESCAPE_BREAK_DISTANCE and recovers-->  GRAZING
##   any      --captured-->                    CAPTURED
##
## Nothing here implements scent, tracks, wind, weather or bait; those are later
## phases. The only randomness is the grazing wander, drawn from an injected
## generator so a seeded hunt replays identically.

signal state_changed(previous: String, current: String)

const GRAZING := "GRAZING"
const ALERTED := "ALERTED"
const FLEEING := "FLEEING"
const ESCAPING := "ESCAPING"
const CAPTURED := "CAPTURED"

## Hunter distance at which the deer notices a threat (metres).
const DETECT_RADIUS := 13.0
## The deer freezes and looks before bolting: prevents a teleport-like reaction.
const ALERT_DURATION := 0.55
## Panic sprint speed. Slightly faster than the hunter, so the first seconds of
## a chase belong to the deer.
const SPRINT_SPEED := 5.6
## Sprint stamina drained per second, and the level at which the deer tires.
const SPRINT_DRAIN := 0.35
const SPRINT_EXIT_STAMINA := 0.25
## Tired but still evasive: slower than the hunter, so sustained pursuit closes.
const ESCAPE_SPEED := 3.4
## Stamina recovered per second while escaping.
const STAMINA_REGEN := 0.06
## Take a second wind only if the hunter gets this close again.
const SECOND_WIND_DISTANCE := 7.5
const SECOND_WIND_STAMINA := 0.45
## If the deer opens this much ground and has recovered, the hunt is lost.
const ESCAPE_BREAK_DISTANCE := 23.0
const ESCAPE_BREAK_STAMINA := 0.60
## Flee direction is re-evaluated on this interval, not every frame, so the deer
## does not jitter left/right while running.
const STEER_INTERVAL := 0.30
## Keeps the deer inside the walkable clearing instead of pinned on the wall.
const WORLD_LIMIT := 41.0
const BOUNDARY_MARGIN := 5.0
## Idle wandering.
const GRAZE_SPEED := 1.05
const GRAZE_WANDER_INTERVAL := 4.0
const GRAZE_PAUSE_CHANCE := 0.35

var state := GRAZING
var stamina := 1.0
var speed := 0.0
var distance_to_hunter := INF
var alert_timer := 0.0

var _flee_dir := Vector3.ZERO
var _steer_timer := 0.0
var _graze_dir := Vector3.ZERO
var _graze_timer := 0.0
var _rng := RandomNumberGenerator.new()


## `seed_value` < 0 randomises (normal play); anything else replays exactly.
func _init(seed_value: int = -1) -> void:
	if seed_value < 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value


## Puts the deer back into a calm grazing state, e.g. for a fresh hunt.
func reset() -> void:
	state = GRAZING
	stamina = 1.0
	speed = 0.0
	alert_timer = 0.0
	distance_to_hunter = INF
	_flee_dir = Vector3.ZERO
	_steer_timer = 0.0
	_graze_timer = 0.0


## Marks the deer captured. Idempotent: later calls do not re-fire the signal.
func capture() -> void:
	if state == CAPTURED:
		return
	_set_state(CAPTURED)
	speed = 0.0


func is_captured() -> bool:
	return state == CAPTURED


## Advances one step and returns the desired planar velocity for this frame.
func update(delta: float, deer_pos: Vector3, hunter_pos: Vector3) -> Vector3:
	var to_hunter := hunter_pos - deer_pos
	to_hunter.y = 0.0
	distance_to_hunter = to_hunter.length()

	match state:
		GRAZING:
			return _update_grazing(delta, deer_pos, to_hunter)
		ALERTED:
			return _update_alerted(delta, to_hunter)
		FLEEING:
			return _update_fleeing(delta, deer_pos, to_hunter)
		ESCAPING:
			return _update_escaping(delta, deer_pos, to_hunter)
		CAPTURED:
			speed = 0.0
			return Vector3.ZERO
	return Vector3.ZERO


func _update_grazing(delta: float, deer_pos: Vector3, to_hunter: Vector3) -> Vector3:
	if distance_to_hunter <= DETECT_RADIUS:
		_set_state(ALERTED)
		alert_timer = ALERT_DURATION
		speed = 0.0
		return Vector3.ZERO

	_graze_timer -= delta
	if _graze_timer <= 0.0:
		_graze_timer = GRAZE_WANDER_INTERVAL * (0.7 + _rng.randf() * 0.6)
		if _rng.randf() < GRAZE_PAUSE_CHANCE:
			_graze_dir = Vector3.ZERO
		else:
			var angle := _rng.randf() * TAU
			_graze_dir = Vector3(cos(angle), 0.0, sin(angle))
		# Drift back toward the middle of the map when grazing far out.
		if Vector2(deer_pos.x, deer_pos.z).length() > WORLD_LIMIT * 0.7:
			_graze_dir = (_graze_dir - deer_pos.normalized() * 1.5).normalized()

	speed = GRAZE_SPEED if _graze_dir.length() > 0.0 else 0.0
	return _graze_dir * speed


func _update_alerted(delta: float, to_hunter: Vector3) -> Vector3:
	speed = 0.0
	# If the hunter backs off during the freeze, the deer settles again.
	if distance_to_hunter > DETECT_RADIUS * 1.35:
		_set_state(GRAZING)
		_graze_timer = 0.0
		return Vector3.ZERO
	alert_timer -= delta
	if alert_timer <= 0.0:
		_set_state(FLEEING)
		_flee_dir = _compute_flee_dir(Vector3.ZERO, to_hunter)
		_steer_timer = STEER_INTERVAL
	return Vector3.ZERO


func _update_fleeing(delta: float, deer_pos: Vector3, to_hunter: Vector3) -> Vector3:
	stamina = maxf(0.0, stamina - SPRINT_DRAIN * delta)
	if stamina <= SPRINT_EXIT_STAMINA:
		_set_state(ESCAPING)
	speed = SPRINT_SPEED
	return _steer(delta, deer_pos, to_hunter) * speed


func _update_escaping(delta: float, deer_pos: Vector3, to_hunter: Vector3) -> Vector3:
	stamina = minf(1.0, stamina + STAMINA_REGEN * delta)
	if distance_to_hunter < SECOND_WIND_DISTANCE and stamina >= SECOND_WIND_STAMINA:
		_set_state(FLEEING)
	elif distance_to_hunter > ESCAPE_BREAK_DISTANCE and stamina >= ESCAPE_BREAK_STAMINA:
		# The deer broke away and has recovered: the hunt is lost, not bugged.
		_set_state(GRAZING)
		_graze_timer = 0.0
		speed = 0.0
		return Vector3.ZERO
	speed = ESCAPE_SPEED
	return _steer(delta, deer_pos, to_hunter) * speed


## Recomputes the flee direction only on STEER_INTERVAL boundaries.
func _steer(delta: float, deer_pos: Vector3, to_hunter: Vector3) -> Vector3:
	_steer_timer -= delta
	if _steer_timer <= 0.0 or _flee_dir.length_squared() < 0.0001:
		_flee_dir = _compute_flee_dir(deer_pos, to_hunter)
		_steer_timer = STEER_INTERVAL
	return _flee_dir


## Away from the hunter, bent toward open ground when the deer nears the edge.
func _compute_flee_dir(deer_pos: Vector3, to_hunter: Vector3) -> Vector3:
	var away := Vector3.ZERO
	if to_hunter.length_squared() > 0.0001:
		away = -to_hunter.normalized()
	else:
		away = Vector3(0, 0, -1)
	if deer_pos == Vector3.ZERO:
		return away
	var inward := Vector3.ZERO
	if deer_pos.x > WORLD_LIMIT - BOUNDARY_MARGIN:
		inward.x -= 1.0
	elif deer_pos.x < -(WORLD_LIMIT - BOUNDARY_MARGIN):
		inward.x += 1.0
	if deer_pos.z > WORLD_LIMIT - BOUNDARY_MARGIN:
		inward.z -= 1.0
	elif deer_pos.z < -(WORLD_LIMIT - BOUNDARY_MARGIN):
		inward.z += 1.0
	if inward.length_squared() < 0.0001:
		return away
	return (away * 0.5 + inward.normalized() * 1.2).normalized()


func _set_state(new_state: String) -> void:
	if state == new_state:
		return
	var previous := state
	state = new_state
	state_changed.emit(previous, new_state)

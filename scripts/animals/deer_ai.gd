extends RefCounted
## Deer behaviour for ATHAR: natural activity, perception, memory and flight.
##
## Free of scene nodes and physics so it can be simulated headless and replayed
## deterministically: update() takes a delta, the deer's position, the hunter's
## position and an optional line-of-sight probe, and returns the desired planar
## velocity. scripts/main.gd applies that velocity to the CharacterBody3D.
##
## Three layers sit under this file and are shared by any future animal:
##   wildlife_profile.gd     species blueprint + seeded personality
##   wildlife_perception.gd  vision cone, hearing, threat memory
##   wildlife_steering.gd    heading smoothing + probe-based avoidance
##
## State flow (calm states are cycled by timers, never per frame):
##
##   GRAZING / WANDERING / OBSERVING / RESTING  --threat seen or heard-->  ALERTED
##   ALERTED --freeze over, threat inside confirm_distance-->  FLEEING
##   ALERTED --freeze over, threat further away-->            INVESTIGATING
##   INVESTIGATING --threat closes in-->                      FLEEING
##   INVESTIGATING --nothing found-->                         RETURNING
##   FLEEING --sprint stamina spent-->                        ESCAPING
##   ESCAPING --hunter closes again-->                        FLEEING
##   ESCAPING --safe distance and recovered-->                RETURNING
##   RETURNING --recovery_time elapses-->                     GRAZING
##   any --captured-->                                        CAPTURED
##
## Drinking is deliberately absent: the world has no water body to drink from,
## and the brief allows it only where a suitable location already exists.
##
## Movement speeds, capture distance and the detection floor are unchanged from
## Phase 3, so the chase balance and every existing test keep their meaning. All
## randomness comes from the injected generator, so a seeded hunt replays
## exactly; personality is rolled from that same generator at construction.

signal state_changed(previous: String, current: String)

const WildlifeProfile := preload("res://scripts/animals/wildlife_profile.gd")
const WildlifePerception := preload("res://scripts/animals/wildlife_perception.gd")
const WildlifeSteering := preload("res://scripts/animals/wildlife_steering.gd")

const GRAZING := "GRAZING"
const WANDERING := "WANDERING"
const OBSERVING := "OBSERVING"
const RESTING := "RESTING"
const ALERTED := "ALERTED"
const INVESTIGATING := "INVESTIGATING"
const FLEEING := "FLEEING"
const ESCAPING := "ESCAPING"
const RETURNING := "RETURNING"
const CAPTURED := "CAPTURED"

const CALM_STATES := [GRAZING, WANDERING, OBSERVING, RESTING]
const ALARM_STATES := [ALERTED, INVESTIGATING, FLEEING, ESCAPING, RETURNING]

## Base sight range, also the floor: personality may widen it, never shrink it,
## so an approaching hunter is always noticed at the distance tuned in Phase 3.
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
## If the deer opens this much ground and has recovered, it stops running.
const ESCAPE_BREAK_DISTANCE := 23.0
const ESCAPE_BREAK_STAMINA := 0.60
## Movement is re-planned on this interval, not every frame, so the deer does not
## jitter left and right while running.
const STEER_INTERVAL := 0.30
## Keeps the deer inside the walkable clearing instead of pinned on the wall.
const WORLD_LIMIT := 41.0
const BOUNDARY_MARGIN := 5.0

## Idle wandering. Unchanged from Phase 3: the walk is scenery, not a chase.
const GRAZE_SPEED := 1.05
const GRAZE_WANDER_INTERVAL := 4.0
const GRAZE_PAUSE_CHANCE := 0.35

## Deer see almost all the way around; only a rear arc is blind.
const VISION_ANGLE_DEGREES := 300.0
## Inside this radius a moving threat is noticed whatever way the deer faces.
const PROXIMITY_RANGE := 10.0
## A sprinting hunter carries this far; a walk barely a third of it.
const HEARING_RANGE := 18.0
## Seconds a threat stays in memory after it is last seen or heard.
const MEMORY_TIME := 6.0
## Seconds of calm walking before the deer relaxes and grazes again.
const RECOVERY_TIME := 4.0
## Distance the deer likes to keep while walking toward an unfamiliar noise.
const INVESTIGATE_DISTANCE := 7.0
## Noise (0..1) at which a sound is worth looking up for.
const NOISE_ALERT_LEVEL := 0.45
## Gain and braking in m/s^2. High enough to look alive, low enough that the
## deer never snaps from standing to full sprint in one frame.
const ACCELERATION := 9.0
const DECELERATION := 14.0
## How eagerly the facing follows the course.
const TURN_RATE := 6.0
## Obstacle probe length and how long a detour is kept.
const AVOID_LOOKAHEAD := 2.8
const AVOID_REFRESH := 0.45
## A state is held at least this long before a timer may change it again.
const MIN_DWELL := 0.9

const ACTIVITY_TEXT := {
	GRAZING: "grazing",
	WANDERING: "wandering",
	OBSERVING: "watching",
	RESTING: "resting",
	ALERTED: "alert",
	INVESTIGATING: "investigating",
	FLEEING: "fleeing",
	ESCAPING: "tiring",
	RETURNING: "settling",
	CAPTURED: "captured",
}

const DEER_BLUEPRINT := {
	"vision_range": DETECT_RADIUS,
	"vision_angle": VISION_ANGLE_DEGREES,
	"proximity_range": PROXIMITY_RANGE,
	"hearing_range": HEARING_RANGE,
	"memory_time": MEMORY_TIME,
	"recovery_time": RECOVERY_TIME,
	"investigate_distance": INVESTIGATE_DISTANCE,
}

var state := GRAZING
var stamina := 1.0
var speed := 0.0
var distance_to_hunter := INF
var alert_timer := 0.0

var profile: RefCounted
var perception: RefCounted
var steering: RefCounted
var home_position := Vector3.ZERO
## True while the deer still remembers a threat it cannot currently see.
var threat_known := false

var _flee_dir := Vector3.ZERO
var _steer_timer := 0.0
var _graze_dir := Vector3.ZERO
var _graze_timer := 0.0
var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var _activity_timer := 0.0
var _return_timer := 0.0
var _dwell := 0.0
var _life_time := 0.0
var _home_set := false
var _rng := RandomNumberGenerator.new()
var _navigation_probe := Callable()


## `seed_value` < 0 randomises (normal play); anything else replays exactly.
func _init(seed_value: int = -1) -> void:
	if seed_value < 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	profile = WildlifeProfile.new()
	profile.setup("deer", DEER_BLUEPRINT, _rng)
	perception = WildlifePerception.new()
	perception.setup(profile)
	steering = WildlifeSteering.new()
	steering.reset()
	_graze_dir = _random_direction()
	_graze_timer = GRAZE_WANDER_INTERVAL * (0.7 + _rng.randf() * 0.6)


## The scene supplies a Callable(from, to) -> bool that answers "is this path
## blocked?" so the deer does not walk into trunks. Tests may leave it unset.
func set_navigation_probe(probe: Callable) -> void:
	_navigation_probe = probe


## Aligns the animal's look direction with its model. main.gd does not need it
## (the brain steers its own facing), but a scene or test that moves the animal
## by hand can keep perception pointing where the model points.
func set_facing(direction: Vector3) -> void:
	steering.reset(direction)


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
	_wander_timer = 0.0
	_activity_timer = 0.0
	_return_timer = 0.0
	_dwell = 0.0
	_life_time = 0.0
	_home_set = false
	threat_known = false
	if perception != null:
		perception.reset()
	if steering != null:
		steering.reset()
	_graze_dir = _random_direction()


## Marks the deer captured. Idempotent: later calls do not re-fire the signal.
func capture() -> void:
	if state == CAPTURED:
		return
	_set_state(CAPTURED)
	speed = 0.0


func is_captured() -> bool:
	return state == CAPTURED


func is_calm() -> bool:
	return state in CALM_STATES


## Short verb for the HUD, e.g. "grazing".
func activity_text() -> String:
	return ACTIVITY_TEXT.get(state, state.to_lower())


## Advances one step and returns the desired planar velocity for this frame.
func update(delta: float, deer_pos: Vector3, hunter_pos: Vector3, los_probe := Callable()) -> Vector3:
	if not _home_set:
		home_position = deer_pos
		_home_set = true
	_life_time += delta
	_dwell += delta
	perception.update(delta, deer_pos, steering.heading, hunter_pos, los_probe)
	distance_to_hunter = perception.distance
	threat_known = perception.threat_known

	match state:
		GRAZING:
			return _update_grazing(delta, deer_pos)
		WANDERING:
			return _update_wandering(delta, deer_pos)
		OBSERVING:
			return _update_observing(delta, deer_pos)
		RESTING:
			return _update_resting(delta, deer_pos)
		ALERTED:
			return _update_alerted(delta, deer_pos)
		INVESTIGATING:
			return _update_investigating(delta, deer_pos)
		FLEEING:
			return _update_fleeing(delta, deer_pos)
		ESCAPING:
			return _update_escaping(delta, deer_pos)
		RETURNING:
			return _update_returning(delta, deer_pos)
		CAPTURED:
			speed = 0.0
			return Vector3.ZERO
	return Vector3.ZERO


# ------------------------------------------------------------- calm activity ---
func _update_grazing(delta: float, deer_pos: Vector3) -> Vector3:
	if _check_alarm():
		return Vector3.ZERO
	_graze_timer -= delta
	if _graze_timer <= 0.0 and _dwell >= MIN_DWELL:
		if not _choose_next_activity(deer_pos):
			return Vector3.ZERO
	return _move(deer_pos, _drift_inward(_graze_dir, deer_pos), _graze_speed_for_dir(), delta, AVOID_REFRESH)


func _update_wandering(delta: float, deer_pos: Vector3) -> Vector3:
	if _check_alarm():
		return Vector3.ZERO
	_wander_timer -= delta
	var to_target := _planar_offset(deer_pos, _wander_target)
	var arrived := to_target.length() < 1.2
	if _wander_timer <= 0.0 or arrived:
		_enter_calm(GRAZING)
		_graze_timer = GRAZE_WANDER_INTERVAL * (0.6 + _rng.randf() * 0.8)
		_graze_dir = _random_direction()
		return _move(deer_pos, Vector3.ZERO, 0.0, delta, AVOID_REFRESH)
	return _move(deer_pos, to_target, GRAZE_SPEED, delta, AVOID_REFRESH)


func _update_observing(delta: float, deer_pos: Vector3) -> Vector3:
	if _check_alarm():
		return Vector3.ZERO
	_activity_timer -= delta
	if _activity_timer <= 0.0 and _dwell >= MIN_DWELL:
		_enter_calm(GRAZING)
		_graze_timer = GRAZE_WANDER_INTERVAL * (0.6 + _rng.randf() * 0.8)
		_graze_dir = _random_direction()
	return _move(deer_pos, Vector3.ZERO, 0.0, delta, AVOID_REFRESH)


func _update_resting(delta: float, deer_pos: Vector3) -> Vector3:
	# A resting deer still keeps one ear on the world: any real alarm wakes it.
	if _check_alarm():
		return Vector3.ZERO
	_activity_timer -= delta
	if _activity_timer <= 0.0 and _dwell >= MIN_DWELL:
		_enter_calm(GRAZING)
		_graze_timer = GRAZE_WANDER_INTERVAL * (0.6 + _rng.randf() * 0.8)
		_graze_dir = _random_direction()
	return _move(deer_pos, Vector3.ZERO, 0.0, delta, AVOID_REFRESH)


## Picks what a calm deer does next. Returns true when the deer keeps grazing.
func _choose_next_activity(deer_pos: Vector3) -> bool:
	var roll := _rng.randf()
	_graze_timer = GRAZE_WANDER_INTERVAL * (0.7 + _rng.randf() * 0.6)
	if roll < 0.52:
		_graze_dir = _pick_graze_direction(deer_pos)
		_dwell = 0.0
		return true
	if roll < 0.70:
		_enter_calm(OBSERVING)
		_activity_timer = 1.8 + _rng.randf() * 1.4
		return false
	if roll < 0.86 or _life_time < 8.0:
		_enter_calm(WANDERING)
		_wander_target = _pick_wander_target(deer_pos)
		_wander_timer = 3.0 + _rng.randf() * 3.0
		return false
	_enter_calm(RESTING)
	_activity_timer = 8.0 + _rng.randf() * 8.0
	return false


func _pick_graze_direction(deer_pos: Vector3) -> Vector3:
	if _rng.randf() < GRAZE_PAUSE_CHANCE:
		return Vector3.ZERO
	return _drift_inward(_random_direction(), deer_pos)


func _pick_wander_target(deer_pos: Vector3) -> Vector3:
	var angle := _rng.randf() * TAU
	var radius := 4.0 + _rng.randf() * 7.0
	var spot := home_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	var limit := WORLD_LIMIT - BOUNDARY_MARGIN
	return Vector3(clampf(spot.x, -limit, limit), 0.0, clampf(spot.z, -limit, limit))


func _graze_speed_for_dir() -> float:
	return GRAZE_SPEED if _graze_dir.length_squared() > 0.0 else 0.0


## Drift back toward the middle of the map when grazing far out.
func _drift_inward(direction: Vector3, deer_pos: Vector3) -> Vector3:
	if Vector2(deer_pos.x, deer_pos.z).length() > WORLD_LIMIT * 0.7:
		var to_centre := _planar_offset(deer_pos, Vector3.ZERO)
		if to_centre.length_squared() > 0.0001:
			return (direction + to_centre.normalized() * 1.5).normalized()
	return direction


func _enter_calm(next_state: String) -> void:
	_set_state(next_state)
	_dwell = 0.0


# --------------------------------------------------------------------- alarm ---
## Notices a threat. Sight is certain; a loud enough sound is enough to look up.
func _check_alarm() -> bool:
	if perception.visible_now:
		_begin_alert()
		return true
	if perception.heard_now and perception.noise_level >= NOISE_ALERT_LEVEL:
		_begin_alert()
		return true
	return false


func _begin_alert() -> void:
	_set_state(ALERTED)
	alert_timer = ALERT_DURATION
	_dwell = 0.0
	speed = 0.0


func _update_alerted(delta: float, deer_pos: Vector3) -> Vector3:
	var out := _move(deer_pos, Vector3.ZERO, 0.0, delta, AVOID_REFRESH)
	# If the threat is gone and out of reach, the deer settles instead of
	# standing frozen forever.
	if not perception.threat_known and perception.distance > profile.vision_range * 1.35:
		_begin_return()
		return out
	alert_timer -= delta
	if alert_timer <= 0.0:
		if perception.threat_known and perception.distance <= profile.confirm_distance:
			_begin_flight(deer_pos)
		elif perception.threat_known:
			_begin_investigation()
		else:
			_begin_return()
	return out


func _begin_flight(deer_pos: Vector3) -> void:
	_set_state(FLEEING)
	_dwell = 0.0
	_flee_dir = _compute_flee_dir(deer_pos)
	_steer_timer = STEER_INTERVAL


func _begin_investigation() -> void:
	_set_state(INVESTIGATING)
	_dwell = 0.0
	_activity_timer = 4.0 + _rng.randf() * 2.0


func _begin_return() -> void:
	_set_state(RETURNING)
	_dwell = 0.0
	_return_timer = 0.0


func _update_investigating(delta: float, deer_pos: Vector3) -> Vector3:
	_activity_timer -= delta
	if perception.visible_now and perception.distance <= profile.confirm_distance:
		_begin_flight(deer_pos)
		return Vector3.ZERO
	var target: Vector3 = perception.threat_position if perception.threat_known else home_position
	var to_threat := _planar_offset(deer_pos, target)
	var close_enough := to_threat.length() <= maxf(profile.investigate_distance, INVESTIGATE_DISTANCE)
	if _activity_timer <= 0.0 or (close_enough and _dwell >= MIN_DWELL):
		_begin_return()
		return _move(deer_pos, Vector3.ZERO, 0.0, delta, AVOID_REFRESH)
	if close_enough:
		# Close enough to judge: stop and look rather than walking into it.
		return _move(deer_pos, Vector3.ZERO, 0.0, delta, AVOID_REFRESH)
	return _move(deer_pos, to_threat, GRAZE_SPEED, delta, AVOID_REFRESH)


func _update_fleeing(delta: float, deer_pos: Vector3) -> Vector3:
	stamina = maxf(0.0, stamina - SPRINT_DRAIN * delta)
	if stamina <= SPRINT_EXIT_STAMINA:
		_set_state(ESCAPING)
		_dwell = 0.0
		return _move(deer_pos, _steer(deer_pos, delta), ESCAPE_SPEED, delta, STEER_INTERVAL)
	return _move(deer_pos, _steer(deer_pos, delta), SPRINT_SPEED, delta, STEER_INTERVAL)


func _update_escaping(delta: float, deer_pos: Vector3) -> Vector3:
	stamina = minf(1.0, stamina + STAMINA_REGEN * delta)
	if distance_to_hunter < SECOND_WIND_DISTANCE and stamina >= SECOND_WIND_STAMINA:
		_begin_flight(deer_pos)
		return _move(deer_pos, _flee_dir, SPRINT_SPEED, delta, STEER_INTERVAL)
	if distance_to_hunter > ESCAPE_BREAK_DISTANCE and stamina >= ESCAPE_BREAK_STAMINA:
		# The deer broke away and has recovered: the hunt is lost, not bugged.
		_begin_return()
		return _move(deer_pos, Vector3.ZERO, 0.0, delta, AVOID_REFRESH)
	return _move(deer_pos, _steer(deer_pos, delta), ESCAPE_SPEED, delta, STEER_INTERVAL)


func _update_returning(delta: float, deer_pos: Vector3) -> Vector3:
	if perception.visible_now or (perception.heard_now and perception.noise_level >= NOISE_ALERT_LEVEL):
		_begin_alert()
		return Vector3.ZERO
	_return_timer += delta
	if _return_timer >= profile.recovery_time:
		_enter_calm(GRAZING)
		_graze_timer = GRAZE_WANDER_INTERVAL * (0.6 + _rng.randf() * 0.8)
		_graze_dir = _pick_graze_direction(deer_pos)
		return _move(deer_pos, _graze_dir, _graze_speed_for_dir(), delta, AVOID_REFRESH)
	var to_home := _planar_offset(deer_pos, home_position)
	if to_home.length() < 1.5:
		return _move(deer_pos, Vector3.ZERO, 0.0, delta, AVOID_REFRESH)
	return _move(deer_pos, to_home, GRAZE_SPEED, delta, AVOID_REFRESH)


# ------------------------------------------------------------------ movement ---
## Recomputes the flight course only on STEER_INTERVAL boundaries.
func _steer(deer_pos: Vector3, delta: float) -> Vector3:
	_steer_timer -= delta
	if _steer_timer <= 0.0 or _flee_dir.length_squared() < 0.0001:
		_flee_dir = _compute_flee_dir(deer_pos)
		_steer_timer = STEER_INTERVAL
	return _flee_dir


## Away from the remembered threat, bent toward open ground near the edge.
func _compute_flee_dir(deer_pos: Vector3) -> Vector3:
	var threat: Vector3 = perception.threat_position if perception.threat_known else deer_pos + Vector3(0.0, 0.0, 1.0)
	var away := _planar_offset(threat, deer_pos)
	if away.length_squared() < 0.0001:
		away = Vector3(0.0, 0.0, -1.0)
	else:
		away = away.normalized()
	if deer_pos == Vector3.ZERO:
		return away
	return _bend_inward(away, deer_pos)


## Turns a course toward open ground when the deer is near the world edge.
func _bend_inward(course: Vector3, deer_pos: Vector3) -> Vector3:
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
		return course
	return (course * 0.5 + inward.normalized() * 1.2).normalized()


## One motion step: avoid obstacles, ease the facing, ramp the speed.
func _move(deer_pos: Vector3, direction: Vector3, target_speed: float, delta: float, refresh: float) -> Vector3:
	var course: Vector3 = steering.avoid(deer_pos, direction, delta, AVOID_LOOKAHEAD, refresh, _navigation_probe)
	steering.turn(delta, course, TURN_RATE)
	var rate := ACCELERATION if target_speed > speed else DECELERATION
	speed = move_toward(speed, target_speed, rate * delta)
	if course == Vector3.ZERO:
		return Vector3.ZERO
	return course * speed


func _random_direction() -> Vector3:
	var angle := _rng.randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle))


func _planar_offset(from: Vector3, to: Vector3) -> Vector3:
	return Vector3(to.x - from.x, 0.0, to.z - from.z)


func _set_state(new_state: String) -> void:
	if state == new_state:
		return
	var previous := state
	state = new_state
	state_changed.emit(previous, new_state)

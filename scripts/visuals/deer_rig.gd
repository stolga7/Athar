extends Node3D
## ATHAR deer, built procedurally from Godot primitive meshes.
##
## Origin is at the hooves and the deer faces -Z (the same convention as the
## hunter). Proportions follow a real deer rather than a stack of spheres:
## deep chest, sloping back, long legs with a rear hock, a two-part neck and a
## narrow muzzle. It carries tined antlers, erect ears and a flicking tail.
##
## The rig owns presentation only. Behaviour (states, detection, fleeing) lives
## in scripts/animals/deer_ai.gd, and the pose is driven by set_state() plus
## animate(), so the same scene can be reused for future animals.
##
## Reads no random numbers; seeded worlds stay byte-identical.

const U := preload("res://scripts/visuals/rig_utils.gd")

## Top of the antlers with the head raised; the body is about 1.2 m at the shoulder.
const HEIGHT := 1.95
const STRIDE_HZ := 1.9

const C_COAT := Color(0.42, 0.28, 0.16)
const C_COAT_DARK := Color(0.27, 0.17, 0.10)
const C_COAT_LIGHT := Color(0.53, 0.38, 0.22)
const C_CREAM := Color(0.80, 0.72, 0.55)
const C_ANTLER := Color(0.76, 0.70, 0.55)
const C_HOOF := Color(0.09, 0.08, 0.07)
const C_EYE := Color(0.05, 0.045, 0.04)
const C_NOSE := Color(0.10, 0.08, 0.08)

var _materials := {}
var _body: Node3D
var _torso: Node3D
var _neck: Node3D
var _head: Node3D
var _ears: Array[Node3D] = []
var _tail: Node3D
var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _leg_rest: Array[float] = []

var _state := "GRAZING"
var _neck_angle := -1.1
var _neck_target := -1.1
var _gait := 0.0
var _breath := 0.0
var _speed := 0.0
## Grazing deer lift their head between bites; this drives that gesture.
var _graze_clock := 0.0
var _lift := 0.0


func _ready() -> void:
	_build()


func _mat(color: Color, roughness := 0.9, metallic := 0.0) -> StandardMaterial3D:
	return U.material(_materials, color, roughness, metallic)


func _build() -> void:
	_body = U.pivot(self, "Body", Vector3(0, 0.95, 0))
	_torso = U.pivot(_body, "Torso", Vector3.ZERO)
	_build_torso()
	_build_neck_and_head()
	_build_legs()
	_build_tail()


func _build_torso() -> void:
	# Barrel of the body, laid along Z by rotating the capsule mesh.
	var barrel := U.part(_torso, U.capsule(0.25, 0.92), _mat(C_COAT), Vector3(0, 0.0, 0.02), Vector3(0.96, 1.0, 0.92))
	barrel.rotation.x = deg_to_rad(90)
	# Deep chest in front, heavier haunch behind.
	U.part(_torso, U.sphere(0.265, 14, 7), _mat(C_COAT), Vector3(0, 0.0, -0.30), Vector3(0.94, 1.0, 0.88))
	U.part(_torso, U.sphere(0.275, 14, 7), _mat(C_COAT_LIGHT), Vector3(0, -0.01, 0.28), Vector3(0.96, 1.02, 0.9))
	# Cream belly and rump patch.
	U.part(_torso, U.sphere(0.20, 12, 6), _mat(C_CREAM), Vector3(0, -0.11, 0.0), Vector3(1.0, 0.45, 1.65))
	U.part(_torso, U.sphere(0.13, 10, 5), _mat(C_CREAM), Vector3(0, 0.06, 0.36), Vector3(1.0, 0.8, 0.5))
	# Shoulder and flank shading breaks up the silhouette.
	for side in [-1, 1]:
		U.part(_torso, U.sphere(0.15, 10, 5), _mat(C_COAT_DARK, 0.95), Vector3(side * 0.17, -0.02, -0.16), Vector3(0.42, 0.9, 0.8))


func _build_neck_and_head() -> void:
	_neck = U.pivot(_torso, "Neck", Vector3(0, 0.13, -0.34))
	var neck := U.part(_neck, U.capsule(0.105, 0.42), _mat(C_COAT), Vector3(0, 0.14, -0.04), Vector3(1.0, 1.0, 0.92))
	neck.rotation.x = deg_to_rad(-28)
	# Darker throat / mane line.
	U.part(_neck, U.capsule(0.075, 0.30), _mat(C_COAT_DARK, 0.95), Vector3(0, 0.10, -0.09), Vector3(1.0, 1.0, 0.8))
	_head = U.pivot(_neck, "Head", Vector3(0, 0.30, -0.14))
	# Skull, tapering into the muzzle.
	U.part(_head, U.sphere(0.118, 14, 7), _mat(C_COAT), Vector3(0, 0.01, -0.02), Vector3(0.92, 0.95, 1.18))
	U.part(_head, U.box(Vector3(0.105, 0.10, 0.20)), _mat(C_COAT_LIGHT), Vector3(0, -0.02, -0.17))
	U.part(_head, U.sphere(0.045, 10, 5), _mat(C_COAT), Vector3(0, 0.0, -0.255), Vector3(1.0, 0.85, 0.8))
	U.part(_head, U.sphere(0.030, 8, 4), _mat(C_NOSE, 0.5), Vector3(0, -0.005, -0.283))
	# Cream chin and jaw.
	U.part(_head, U.box(Vector3(0.09, 0.035, 0.17)), _mat(C_CREAM), Vector3(0, -0.075, -0.16))
	for side in [-1, 1]:
		U.part(_head, U.sphere(0.022, 8, 4), _mat(C_EYE, 0.35), Vector3(side * 0.072, 0.035, -0.10))
		# Pale ring around the eye, typical of wild deer.
		U.part(_head, U.sphere(0.040, 8, 4), _mat(C_CREAM), Vector3(side * 0.068, 0.035, -0.085), Vector3(0.55, 0.55, 0.35))
	_build_ears()
	_build_antlers()


func _build_ears() -> void:
	for side in [-1, 1]:
		var ear := U.pivot(_head, "Ear%s" % ("L" if side < 0 else "R"), Vector3(side * 0.10, 0.085, 0.01))
		var outer := U.part(ear, U.tapered(0.006, 0.052, 0.17, 8), _mat(C_COAT), Vector3(0, 0.085, 0), Vector3(1.0, 1.0, 0.5))
		outer.rotation.z = deg_to_rad(side * -24)
		var inner := U.part(ear, U.tapered(0.004, 0.035, 0.13, 8), _mat(C_CREAM), Vector3(0, 0.085, -0.012), Vector3(1.0, 1.0, 0.35))
		inner.rotation.z = deg_to_rad(side * -24)
		_ears.append(ear)


func _build_antlers() -> void:
	for side in [-1, 1]:
		var base := Vector3(side * 0.055, 0.10, 0.0)
		var beam_tip := Vector3(side * 0.20, 0.36, 0.13)
		U.strut(_head, base, beam_tip, 0.019, _mat(C_ANTLER, 0.8))
		# Brow tine sweeping forward, then two tines up the beam.
		U.strut(_head, base + Vector3(0, 0.04, 0), Vector3(side * 0.13, 0.20, -0.16), 0.013, _mat(C_ANTLER, 0.8))
		U.strut(_head, base.lerp(beam_tip, 0.45), base.lerp(beam_tip, 0.45) + Vector3(side * 0.06, 0.15, -0.02), 0.012, _mat(C_ANTLER, 0.8))
		U.strut(_head, base.lerp(beam_tip, 0.75), base.lerp(beam_tip, 0.75) + Vector3(side * 0.05, 0.13, 0.02), 0.010, _mat(C_ANTLER, 0.8))
		# Knobby burr where the antler meets the skull.
		U.part(_head, U.sphere(0.028, 8, 4), _mat(C_ANTLER, 0.8), base)


func _build_legs() -> void:
	# Front pair sits under the chest, rear pair under the haunch with a hock.
	var layout := [
		{"name": "FrontL", "x": -0.145, "z": -0.25, "rest": 0.0, "rear": false},
		{"name": "FrontR", "x": 0.145, "z": -0.25, "rest": 0.0, "rear": false},
		{"name": "RearL", "x": -0.155, "z": 0.27, "rest": 0.20, "rear": true},
		{"name": "RearR", "x": 0.155, "z": 0.27, "rest": 0.20, "rear": true},
	]
	for leg in layout:
		var upper := U.pivot(_torso, "Leg%s" % leg["name"], Vector3(leg["x"], -0.13, leg["z"]))
		upper.rotation.x = leg["rest"]
		U.part(upper, U.capsule(0.055, 0.40), _mat(C_COAT), Vector3(0, -0.20, 0), Vector3(1.0, 1.0, 0.9))
		var lower := U.pivot(upper, "Knee%s" % leg["name"], Vector3(0, -0.39, 0))
		# The rear lower leg angles back into the hock.
		lower.rotation.x = -leg["rest"] - 0.15
		U.part(lower, U.capsule(0.040, 0.38), _mat(C_COAT_DARK, 0.95), Vector3(0, -0.19, 0), Vector3(1.0, 1.0, 0.9))
		U.part(lower, U.box(Vector3(0.068, 0.06, 0.09)), _mat(C_HOOF, 0.7), Vector3(0, -0.395, -0.012))
		_legs.append(upper)
		_knees.append(lower)
		_leg_rest.append(leg["rest"])


func _build_tail() -> void:
	_tail = U.pivot(_torso, "Tail", Vector3(0, 0.10, 0.40))
	U.strut(_tail, Vector3.ZERO, Vector3(0, -0.09, 0.14), 0.022, _mat(C_COAT))
	U.part(_tail, U.sphere(0.045, 8, 4), _mat(C_CREAM), Vector3(0, -0.10, 0.16), Vector3(1.0, 0.8, 1.2))


## Presentation hint from the behaviour layer. Purely cosmetic: it changes the
## head/ear/tail pose, never the movement decision.
func set_state(state: String) -> void:
	if _state == state:
		return
	_state = state
	match state:
		"GRAZING":
			_neck_target = -1.15
		"WANDERING":
			_neck_target = -0.55
		"OBSERVING":
			_neck_target = 0.12
		"RESTING":
			_neck_target = -0.28
		"RETURNING":
			_neck_target = -0.80
		"INVESTIGATING":
			_neck_target = 0.16
		"ALERTED":
			_neck_target = 0.22
		"FLEEING", "ESCAPING":
			_neck_target = -0.30
		"CAPTURED":
			_neck_target = -1.05
		_:
			_neck_target = -0.30


## Advances the pose. `speed` is the planar speed in metres per second.
func animate(delta: float, speed: float) -> void:
	if _neck == null:
		return
	_speed = speed
	_breath += delta * 1.7
	var gait := clampf(speed / 5.4, 0.0, 1.0)
	if gait > 0.02:
		_gait += delta * TAU * STRIDE_HZ * (0.5 + 0.6 * gait)

	# Grazing deer stop chewing and lift their head every few seconds, then drop
	# back to the grass. Purely a rhythm, no random numbers.
	if _state == "GRAZING":
		_graze_clock += delta
		var cycle := fmod(_graze_clock, 9.0)
		_lift = lerpf(_lift, 1.0 if cycle > 7.3 else 0.0, minf(1.0, delta * 2.6))
	else:
		_lift = lerpf(_lift, 0.0, minf(1.0, delta * 3.4))
	var neck_target := _neck_target
	if _state == "GRAZING":
		neck_target = lerpf(_neck_target, -0.42, _lift)

	_neck_angle = lerp_angle(_neck_angle, neck_target, minf(1.0, delta * 4.5))
	_neck.rotation.x = _neck_angle
	# Grazing deer nudge their head along the ground; alert deer hold it still.
	if _state == "GRAZING":
		_neck.rotation.x += sin(_breath * 0.9) * 0.09
		_head.rotation.x = lerpf(0.55 + sin(_breath * 0.7) * 0.06, 0.06, _lift)
	elif _state == "OBSERVING":
		# Slow scanning sweep: the animal is reading the treeline, not frozen.
		_head.rotation.x = lerpf(_head.rotation.x, 0.02, delta * 3.0)
		_head.rotation.y = sin(_breath * 0.38) * 0.34
	elif _state == "RESTING":
		_head.rotation.x = lerpf(_head.rotation.x, 0.14, delta * 2.4)
		_head.rotation.y = lerpf(_head.rotation.y, 0.0, delta * 2.0)
	else:
		var pitch := 0.10 + (0.14 if _state == "ALERTED" else 0.0) + (0.05 if _state == "INVESTIGATING" else 0.0)
		_head.rotation.x = lerpf(_head.rotation.x, pitch, delta * 5.0)
		_head.rotation.y = sin(_breath * 0.6) * 0.10 * (1.0 - gait)

	# Ears: relaxed at rest, pricked upright and forward when alert or fleeing.
	var pricked := _state in ["ALERTED", "FLEEING", "ESCAPING", "INVESTIGATING"]
	var ear_spread := 0.42 if pricked else 0.30
	for i in range(_ears.size()):
		var side := -1.0 if i == 0 else 1.0
		_ears[i].rotation.z = -side * ear_spread
		_ears[i].rotation.x = -0.25 if pricked else 0.0

	# Tail: low and flicking while grazing, flagged up when running away.
	var tail_lift := 0.0
	if _state in ["FLEEING", "ESCAPING"]:
		tail_lift = 1.1
	elif _state == "ALERTED" or _state == "INVESTIGATING":
		tail_lift = 0.45
	_tail.rotation.x = lerpf(_tail.rotation.x, tail_lift, delta * 6.0)
	_tail.rotation.y = sin(_breath * 2.2) * 0.25 * (1.0 - gait * 0.5)

	# Four-beat walk that compresses into a bounding gallop at speed. Even a slow
	# walk keeps a visible stride, so a wandering deer never looks like it glides.
	var offsets := [0.0, 0.55, PI, PI + 0.55]
	var stride := gait
	if speed > 0.15:
		stride = maxf(gait, 0.32)
	var amplitude := lerpf(0.34, 0.95, stride)
	var bounce := absf(sin(_gait)) * 0.075 * stride
	for i in range(_legs.size()):
		var swing := sin(_gait + offsets[i])
		_legs[i].rotation.x = _leg_rest[i] + swing * amplitude * stride
		_knees[i].rotation.x = -_leg_rest[i] - 0.15 + maxf(0.0, swing) * 0.85 * stride

	_torso.rotation.x = sin(_gait) * 0.06 * gait
	_body.position.y = 0.95 + bounce + sin(_breath) * 0.004 * (1.0 - gait)

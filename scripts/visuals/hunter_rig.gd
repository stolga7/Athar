extends Node3D
## ATHAR hunter, built procedurally from Godot primitive meshes.
##
## Origin is at the feet and the character faces -Z, matching the movement code
## in scripts/main.gd. The silhouette is a hooded wilderness hunter: layered
## cloak over a tunic, leather belt and boots, a quiver on the back and a bow
## carried in the left hand. No imported model, no downloaded asset, no paid
## animation library, and no graphic weapon detail.
##
## Every limb hangs off a plain Node3D joint, so the walk and run cycles are
## real rotations of hip/knee/shoulder/elbow pivots rather than a sliding body.
## The rig reads no random numbers, so it cannot disturb the seeded world.

const U := preload("res://scripts/visuals/rig_utils.gd")

## Height including the hood tip; the collider in main.gd is slightly shorter.
const HEIGHT := 2.0
## Stride frequency in steps per second at full speed.
const STRIDE_HZ := 1.75
## Speed at which the run cycle reaches full amplitude.
const RUN_SPEED := 4.4

# Palette: dark wilderness tones with purple cloth, gold trim, and one
# restrained cyan detail. Same colour language as the rest of ATHAR.
const C_CLOAK := Color(0.17, 0.14, 0.22)
const C_CLOAK_DARK := Color(0.10, 0.085, 0.135)
const C_TUNIC := Color(0.20, 0.24, 0.20)
const C_LEATHER := Color(0.20, 0.14, 0.10)
const C_LEATHER_LIGHT := Color(0.33, 0.23, 0.14)
const C_GOLD := Color(0.74, 0.58, 0.27)
const C_SKIN := Color(0.60, 0.45, 0.31)
const C_CYAN := Color(0.36, 0.74, 0.74)
const C_WOOD := Color(0.31, 0.21, 0.12)
const C_STRING := Color(0.82, 0.79, 0.68)

var _materials := {}
var _body: Node3D
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _cloak: Node3D
var _quiver: Node3D
var _bow: Node3D
var _thighs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _elbows: Array[Node3D] = []

var _phase := 0.0
var _breath := 0.0
var _speed := 0.0

func _ready() -> void:
	_build()


func _mat(color: Color, roughness := 0.85, metallic := 0.0) -> StandardMaterial3D:
	return U.material(_materials, color, roughness, metallic)


func _build() -> void:
	_body = U.pivot(self, "Body", Vector3.ZERO)
	_hips = U.pivot(_body, "Hips", Vector3(0, 0.92, 0))
	_build_pelvis()
	_torso = U.pivot(_hips, "Torso", Vector3(0, 0.16, 0))
	_build_torso()
	_build_head()
	_build_arms()
	_build_legs()
	_build_gear()


func _build_pelvis() -> void:
	U.part(_hips, U.box(Vector3(0.30, 0.22, 0.23)), _mat(C_LEATHER), Vector3.ZERO)
	# Belt with a gold buckle and a single cyan gem.
	var belt := U.tapered(0.215, 0.225, 0.085, 14)
	U.part(_hips, belt, _mat(C_LEATHER_LIGHT, 0.7), Vector3(0, 0.05, 0))
	U.part(_hips, U.box(Vector3(0.11, 0.09, 0.05)), _mat(C_GOLD, 0.35, 0.7), Vector3(0, 0.05, -0.21))
	U.part(_hips, U.sphere(0.028, 10, 5), U.glow(_materials, C_CYAN, 1.2), Vector3(0, 0.05, -0.235))
	# Belt pouch.
	U.part(_hips, U.box(Vector3(0.13, 0.11, 0.08)), _mat(C_LEATHER_LIGHT, 0.9), Vector3(0.20, 0.0, -0.02))


func _build_torso() -> void:
	# Chest is a slightly flattened capsule so the shoulders read as shoulders.
	U.part(_torso, U.capsule(0.21, 0.58), _mat(C_TUNIC), Vector3(0, 0.22, 0), Vector3(1.08, 1.0, 0.86))
	# Leather strap across the chest, holding the quiver.
	var strap := U.part(_torso, U.box(Vector3(0.075, 0.52, 0.035)), _mat(C_LEATHER_LIGHT, 0.9), Vector3(0, 0.26, -0.175))
	strap.rotation.z = deg_to_rad(24)
	# Cloak: a wide open cone hanging from the shoulders, on its own pivot so it
	# can sway one frame behind the body.
	_cloak = U.pivot(_torso, "Cloak", Vector3(0, 0.46, 0.02))
	U.part(_cloak, U.tapered(0.20, 0.42, 0.90, 16), _mat(C_CLOAK, 0.95), Vector3(0, -0.44, 0), Vector3(1.0, 1.0, 0.88))
	# Collar / mantle over the shoulders.
	U.part(_cloak, U.sphere(0.19, 14, 6), _mat(C_CLOAK_DARK, 0.95), Vector3(0, 0.0, 0), Vector3(1.35, 0.5, 1.25))
	# Gold cloak clasp at the throat.
	U.part(_torso, U.tapered(0.05, 0.05, 0.03, 8), _mat(C_GOLD, 0.35, 0.7), Vector3(0, 0.47, -0.17))
	# Neck.
	U.part(_torso, U.tapered(0.075, 0.085, 0.14, 8), _mat(C_SKIN, 0.8), Vector3(0, 0.56, 0.0))


func _build_head() -> void:
	_head = U.pivot(_torso, "Head", Vector3(0, 0.64, 0))
	# Face sits slightly forward inside the hood opening.
	U.part(_head, U.sphere(0.125, 14, 8), _mat(C_SKIN, 0.8), Vector3(0, 0.02, -0.02), Vector3(0.95, 1.05, 0.95))
	# Hood shell, offset back so the face stays readable.
	U.part(_head, U.sphere(0.185, 14, 8), _mat(C_CLOAK_DARK, 0.95), Vector3(0, 0.05, 0.045), Vector3(1.02, 1.06, 1.02))
	# Pointed hood tip, tipped slightly back.
	var point := U.part(_head, U.cone(0.115, 0.28, 12), _mat(C_CLOAK, 0.95), Vector3(0, 0.24, 0.07))
	point.rotation.x = deg_to_rad(16)
	# Gold trim around the hood opening.
	var trim := U.part(_head, _ring(0.115, 0.142), _mat(C_GOLD, 0.4, 0.6), Vector3(0, 0.03, -0.055))
	trim.rotation.x = deg_to_rad(90)
	# Eyes inside the hood shadow.
	for side in [-1, 1]:
		U.part(_head, U.sphere(0.016, 8, 4), _mat(Color(0.06, 0.05, 0.05), 0.5), Vector3(side * 0.044, 0.045, -0.125))
	# Short beard / face shadow mass.
	U.part(_head, U.sphere(0.085, 10, 5), _mat(Color(0.16, 0.12, 0.09), 0.9), Vector3(0, -0.055, -0.075), Vector3(1.0, 0.7, 0.9))


func _build_arms() -> void:
	for side in [-1, 1]:
		var shoulder := U.pivot(_torso, "Shoulder%s" % ("L" if side < 0 else "R"), Vector3(side * 0.245, 0.42, 0))
		# Layered shoulder pad in cloak cloth.
		U.part(shoulder, U.sphere(0.115, 12, 6), _mat(C_CLOAK, 0.95), Vector3(side * 0.015, 0.01, 0), Vector3(1.1, 0.85, 1.05))
		U.part(shoulder, U.capsule(0.062, 0.32), _mat(C_TUNIC), Vector3(0, -0.16, 0))
		var elbow := U.pivot(shoulder, "Elbow%s" % ("L" if side < 0 else "R"), Vector3(0, -0.32, 0))
		U.part(elbow, U.capsule(0.052, 0.28), _mat(C_TUNIC), Vector3(0, -0.14, 0))
		# Leather bracer.
		U.part(elbow, U.tapered(0.060, 0.058, 0.11, 8), _mat(C_LEATHER_LIGHT, 0.85), Vector3(0, -0.20, 0))
		# Gloved hand.
		U.part(elbow, U.sphere(0.058, 10, 5), _mat(C_LEATHER, 0.85), Vector3(0, -0.30, 0), Vector3(0.9, 1.0, 1.05))
		_arms.append(shoulder)
		_elbows.append(elbow)
		if side < 0:
			_build_bow(elbow)


func _build_bow(elbow: Node3D) -> void:
	# The bow hangs from the left hand as a shallow arc, with a plain string.
	_bow = U.pivot(elbow, "Bow", Vector3(0, -0.32, -0.02))
	var points := [
		Vector3(0, -0.56, 0.02),
		Vector3(0, -0.32, -0.09),
		Vector3(0, 0.0, -0.13),
		Vector3(0, 0.32, -0.09),
		Vector3(0, 0.56, 0.02),
	]
	for i in range(points.size() - 1):
		U.strut(_bow, points[i], points[i + 1], 0.017, _mat(C_WOOD, 0.7))
	# String between the tips, thin enough to read as a bow rather than a rod.
	U.strut(_bow, points[0], points[4], 0.005, _mat(C_STRING, 0.6))
	# Gold nocks and a wrapped grip with the singe cyan accent.
	for tip in [points[0], points[4]]:
		U.part(_bow, U.sphere(0.021, 8, 4), _mat(C_GOLD, 0.4, 0.6), tip)
	U.part(_bow, U.tapered(0.026, 0.026, 0.16, 8), _mat(C_LEATHER, 0.85), Vector3(0, 0, -0.125))
	U.part(_bow, U.tapered(0.030, 0.030, 0.03, 8), U.glow(_materials, C_CYAN, 0.9), Vector3(0, 0.0, -0.125))


func _build_legs() -> void:
	for side in [-1, 1]:
		var hip := U.pivot(_hips, "Hip%s" % ("L" if side < 0 else "R"), Vector3(side * 0.108, -0.11, 0))
		U.part(hip, U.capsule(0.084, 0.36), _mat(C_TUNIC, 0.9), Vector3(0, -0.17, 0))
		var knee := U.pivot(hip, "Knee%s" % ("L" if side < 0 else "R"), Vector3(0, -0.36, 0))
		U.part(knee, U.capsule(0.068, 0.34), _mat(C_TUNIC, 0.9), Vector3(0, -0.16, 0))
		# Boot: shaft, foot and a darker sole.
		U.part(knee, U.tapered(0.082, 0.078, 0.18, 8), _mat(C_LEATHER, 0.85), Vector3(0, -0.30, 0))
		U.part(knee, U.box(Vector3(0.15, 0.13, 0.27)), _mat(C_LEATHER, 0.85), Vector3(0, -0.375, -0.035))
		U.part(knee, U.box(Vector3(0.155, 0.035, 0.285)), _mat(Color(0.09, 0.08, 0.08), 0.9), Vector3(0, -0.437, -0.035))
		_thighs.append(hip)
		_knees.append(knee)


func _build_gear() -> void:
	# Quiver on the back, tilted so it reads from the game camera.
	_quiver = U.pivot(_torso, "Quiver", Vector3(0.17, 0.30, 0.18))
	_quiver.rotation = Vector3(deg_to_rad(12), 0, deg_to_rad(-14))
	U.part(_quiver, U.tapered(0.075, 0.062, 0.42, 10), _mat(C_LEATHER, 0.85), Vector3.ZERO)
	U.part(_quiver, U.tapered(0.079, 0.079, 0.05, 10), _mat(C_LEATHER_LIGHT, 0.8), Vector3(0, 0.20, 0))
	for i in range(3):
		var a := (i - 1) * 0.035
		var base := Vector3(a, 0.20, 0.01)
		U.strut(_quiver, base, base + Vector3(a * 0.4, 0.20, 0.0), 0.008, _mat(C_WOOD, 0.7))
		U.part(_quiver, U.box(Vector3(0.022, 0.05, 0.012)), _mat(C_GOLD, 0.6), base + Vector3(a * 0.4, 0.225, 0.0))
	# Small cyan rune-stone hanging from the belt, tying the hunter to ATHAR's
	# restrained magic accents.
	U.part(_torso, U.sphere(0.035, 8, 4), U.glow(_materials, C_CYAN, 0.8), Vector3(-0.19, 0.34, -0.12))


## A thin ring built from a very short, wide open cylinder (hood trim).
func _ring(inner: float, outer: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = outer
	m.bottom_radius = outer
	m.height = 0.012
	m.radial_segments = 16
	m.rings = 1
	m.cap_top = false
	m.cap_bottom = false
	return m


## Advances the idle/walk/run presentation. `speed` is the planar speed of the
## CharacterBody3D in metres per second; nothing here moves the body itself.
func animate(delta: float, speed: float) -> void:
	_speed = speed
	var gait := clampf(speed / RUN_SPEED, 0.0, 1.0)
	var step_phase := 0.0
	if gait > 0.02:
		_phase += delta * TAU * STRIDE_HZ * (0.55 + 0.45 * gait)
		step_phase = _phase
	_breath += delta * 1.5

	# Body bob: one dip per footfall, plus a gentle idle breath.
	var bob := -absf(sin(step_phase)) * 0.035 * gait
	_body.position.y = bob + sin(_breath) * 0.006 * (1.0 - gait)

	# Torso leans forward as the hunter runs.
	_torso.rotation.x = lerpf(_torso.rotation.x, -0.10 * gait, delta * 8.0)
	_torso.rotation.z = sin(step_phase) * 0.02 * gait

	# Legs: opposite phases, knees bending on the trailing swing.
	for i in range(_thighs.size()):
		var swing := sin(step_phase + (0.0 if i == 0 else PI))
		_thighs[i].rotation.x = swing * 0.75 * gait
		_knees[i].rotation.x = -maxf(0.0, -swing) * 1.05 * gait

	# Arms counter-swing against the legs; the bow arm swings less.
	for i in range(_arms.size()):
		var swing := sin(step_phase + (PI if i == 0 else 0.0))
		var scale := 0.55 if i == 0 else 0.8
		_arms[i].rotation.x = swing * scale * gait
		_arms[i].rotation.z = (0.06 if i == 0 else -0.06) * (1.0 - gait * 0.5)
		_elbows[i].rotation.x = -0.35 - maxf(0.0, swing) * 0.45 * gait

	# Cloak trails behind the run and sways in the idle breeze.
	_cloak.rotation.x = -0.06 - 0.30 * gait + sin(step_phase * 2.0) * 0.03 * gait
	_cloak.rotation.z = sin(_breath * 0.8) * 0.02 + sin(step_phase) * 0.02 * gait

	# Head stays level: it counters the torso lean and scans slightly at rest.
	_head.rotation.x = 0.10 * gait + sin(_breath * 0.7) * 0.02 * (1.0 - gait)
	_head.rotation.y = sin(_breath * 0.45) * 0.12 * (1.0 - gait)

	# Quiver and bow inherit the body motion with a small independent lag.
	_quiver.rotation.z = deg_to_rad(-14) + sin(step_phase) * 0.05 * gait
	if _bow:
		_bow.rotation.x = -0.20 * gait + sin(step_phase) * 0.05 * gait
		_bow.rotation.z = sin(_breath * 0.9) * 0.02

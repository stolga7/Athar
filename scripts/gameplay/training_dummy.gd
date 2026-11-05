extends Node3D
## A straw training target used to prove the combat system.
##
## The overhaul deliberately does not add enemies or bosses: the requirement was
## to make the player's combat readable first. This target is a prop, not a
## character: a wooden post, a straw bale and a painted ring. It takes damage,
## flashes, recoils and can be reset, which is everything the combat tests need.

signal damaged(amount: float, remaining: float)
signal destroyed

const U := preload("res://scripts/visuals/rig_utils.gd")

const MAX_HEALTH := 120.0
## How far the target leans back when hit, in radians.
const RECOIL := 0.20
const RECOIL_RATE := 9.0

var health := MAX_HEALTH
var hits := 0
## Set while the target is leaning back from the last hit.
var recoil := 0.0

var _pivot: Node3D
var _flash: StandardMaterial3D
var _flash_time := 0.0
var _materials := {}


func _ready() -> void:
	_build()


func _build() -> void:
	_pivot = U.pivot(self, "Pivot", Vector3.ZERO)
	var post := U.material(_materials, Color(0.24, 0.17, 0.11), 0.9)
	U.part(_pivot, U.tapered(0.075, 0.09, 1.35, 10), post, Vector3(0, 0.68, 0))
	# Crossbar and two braced legs, so it reads as something built, not a stick.
	U.part(_pivot, U.box(Vector3(0.9, 0.09, 0.09)), post, Vector3(0, 1.18, 0))
	for side in [-1, 1]:
		var leg := U.part(_pivot, U.tapered(0.045, 0.05, 0.85, 8), post, Vector3(side * 0.28, 0.38, 0.05))
		leg.rotation.z = deg_to_rad(side * 16.0)
	_flash = U.material(_materials, Color(0.46, 0.38, 0.22), 0.98)
	U.part(_pivot, U.sphere(0.30, 16, 10), _flash, Vector3(0, 1.10, 0.06), Vector3(1.0, 0.88, 0.62))
	# Painted rings on the straw face.
	var paint := U.material(_materials, Color(0.62, 0.16, 0.13), 0.8)
	for ring in [[0.28, 0.205], [0.13, 0.095]]:
		var mesh := CylinderMesh.new()
		mesh.top_radius = float(ring[0])
		mesh.bottom_radius = float(ring[1])
		mesh.height = 0.012
		mesh.radial_segments = 20
		mesh.rings = 1
		mesh.cap_top = false
		mesh.cap_bottom = false
		var part := U.part(_pivot, mesh, paint, Vector3(0, 1.10, 0.20))
		part.rotation.x = deg_to_rad(90)
	U.part(_pivot, U.sphere(0.085, 12, 6), U.material(_materials, Color(0.86, 0.80, 0.62), 0.9), Vector3(0, 1.10, 0.205), Vector3(1.0, 1.0, 0.4))
	# A small collision body so the target blocks the hunter like any prop.
	var body := StaticBody3D.new()
	body.name = "TargetBody"
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.5
	shape.shape = capsule
	shape.position.y = 0.78
	body.add_child(shape)
	add_child(body)


## Applies damage and returns the remaining health. Fortified while recoiling is
## irrelevant: every clean hit counts, so the combat tests can predict totals.
func damage(amount: float) -> float:
	if health <= 0.0:
		return 0.0
	health = maxf(0.0, health - amount)
	hits += 1
	recoil = 1.0
	_flash_time = 0.12
	damaged.emit(amount, health)
	if health <= 0.0:
		destroyed.emit()
	return health


func reset() -> void:
	health = MAX_HEALTH
	hits = 0
	recoil = 0.0
	_flash_time = 0.0
	if _pivot != null:
		_pivot.rotation = Vector3.ZERO


func is_down() -> bool:
	return health <= 0.0


func _process(delta: float) -> void:
	if _pivot == null:
		return
	recoil = maxf(0.0, recoil - delta * 2.4)
	_pivot.rotation.x = -recoil * RECOIL
	if _flash_time > 0.0:
		_flash_time -= delta
		_flash.emission_enabled = true
		_flash.emission = Color(0.95, 0.55, 0.30)
		_flash.emission_energy_multiplier = 0.9
	else:
		_flash.emission_enabled = false
	# A downed target slumps forward instead of disappearing.
	if is_down():
		_pivot.rotation.x = lerpf(_pivot.rotation.x, deg_to_rad(-74.0), minf(1.0, delta * 4.0))

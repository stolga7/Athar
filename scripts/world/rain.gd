extends RefCounted
## Rain for the ATHAR wilderness.
##
## One GPUParticles3D emitter with a single unshaded quad; the CPU never touches
## a drop. It is capped at PARTICLE_COUNT, emits from a box that follows the
## hunter instead of covering the whole map, casts no shadow and is simply turned
## off when the weather is dry.
##
## Intensity is driven by `amount_ratio` rather than by respawning the system, so
## rain eases in and out with the weather blend instead of popping on.

const PARTICLE_COUNT := 700
## Half-extents of the emission box, in metres, around the hunter.
const BOX_EXTENTS := Vector3(16.0, 4.0, 16.0)
## Height above the hunter the emitter is parked at.
const EMIT_HEIGHT := 10.0
const LIFETIME := 1.15
## Fast enough to read as rain, slow enough to stay cheap and not blink.
const FALL_SPEED_MIN := 12.0
const FALL_SPEED_MAX := 15.0

const DROP_COLOR := Color(0.64, 0.72, 0.86, 0.30)


static func build(parent: Node3D) -> Dictionary:
	var streak := QuadMesh.new()
	streak.size = Vector2(0.022, 0.62)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = DROP_COLOR
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	streak.material = material

	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, -1.0, 0.0)
	process.spread = 3.0
	process.initial_velocity_min = FALL_SPEED_MIN
	process.initial_velocity_max = FALL_SPEED_MAX
	process.gravity = Vector3(0.0, -5.0, 0.0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = BOX_EXTENTS
	process.scale_min = 0.75
	process.scale_max = 1.25
	process.lifetime_randomness = 0.3

	var node := GPUParticles3D.new()
	node.name = "Rain"
	node.amount = PARTICLE_COUNT
	node.lifetime = LIFETIME
	node.preprocess = 0.8
	node.randomness = 0.35
	node.local_coords = false
	node.draw_pass_1 = streak
	node.process_material = process
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_aabb = AABB(Vector3(-30, -18, -30), Vector3(60, 36, 60))
	node.emitting = false
	node.amount_ratio = 0.0
	parent.add_child(node)

	return {
		"node": node,
		"material": material,
		"process": process,
		"amount": PARTICLE_COUNT,
	}


## Places the emitter over the player, applies intensity and lets a little wind
## slant the fall.
static func apply(info: Dictionary, hunter_position: Vector3, intensity: float, wind: float) -> void:
	var node: GPUParticles3D = info["node"]
	if node == null:
		return
	var amount := clampf(intensity, 0.0, 1.0)
	node.global_position = hunter_position + Vector3(0.0, EMIT_HEIGHT, 0.0)
	node.rotation_degrees = Vector3(0.0, 0.0, -5.0 * wind)
	node.amount_ratio = amount
	node.emitting = amount > 0.02

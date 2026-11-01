extends RefCounted
## Lighting and atmosphere for the ATHAR wilderness.
##
## The prototype used a single hard sun, flat colour ambient light and thin fog,
## which produced an evenly lit olive field with near-black shadow blobs: no
## depth, no mood, and poor silhouette contrast between hunter, deer and trees.
##
## This builder keeps the same cheap setup the mobile renderer likes - one
## shadow-casting directional light and one shadowless fill light, no glow, no
## SSAO - and spends it differently:
##
##   * a low, warm dusk sun with soft-edged shadows and a shadow opacity under
##     1.0, so shade is readable instead of black,
##   * a cool violet-cyan fill from the opposite side, which separates the
##     hunter's cloak and the deer's coat from a wall of green,
##   * a deep sky and depth fog tuned to fade distant trunks without hiding a
##     deer at 20 metres,
##   * filmic tonemapping with a small contrast/saturation lift.
##
## All values are named so the visual tests can assert the setup instead of
## trusting a screenshot alone.

const SUN_COLOR := Color(1.0, 0.92, 0.80)
const SUN_ENERGY := 1.55
const SUN_ROTATION := Vector3(-44.0, -40.0, 0.0)
## Soft, wide penumbra: 1.1 degrees of angular diameter, plus blur.
const SUN_ANGULAR_DIAMETER := 1.1
const SUN_SHADOW_BLUR := 1.6
const SUN_SHADOW_OPACITY := 0.78
const SUN_SHADOW_MAX_DISTANCE := 42.0

const FILL_COLOR := Color(0.45, 0.55, 0.80)
const FILL_ENERGY := 0.30
const FILL_ROTATION := Vector3(-24.0, 145.0, 0.0)

const AMBIENT_COLOR := Color(0.34, 0.35, 0.375)
const AMBIENT_ENERGY := 1.00

const FOG_COLOR := Color(0.118, 0.138, 0.142)
const FOG_DENSITY := 0.0095
const FOG_SKY_AFFECT := 0.85

const SKY_TOP := Color(0.042, 0.068, 0.088)
const SKY_HORIZON := Color(0.150, 0.158, 0.155)
const SKY_GROUND_HORIZON := Color(0.062, 0.072, 0.062)
const SKY_GROUND_BOTTOM := Color(0.020, 0.028, 0.024)


## Adds the environment and both lights to `parent`. Returns the pieces so the
## tests can inspect them without searching the tree.
static func build(parent: Node3D) -> Dictionary:
	var world_env := WorldEnvironment.new()
	world_env.name = "WildsEnvironment"
	var env := Environment.new()

	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = SKY_TOP
	sky_material.sky_horizon_color = SKY_HORIZON
	sky_material.ground_bottom_color = SKY_GROUND_BOTTOM
	sky_material.ground_horizon_color = SKY_GROUND_HORIZON
	sky_material.sun_angle_max = 22.0
	sky_material.sun_curve = 0.12
	sky_material.sky_energy_multiplier = 0.68
	sky_material.ground_energy_multiplier = 0.7
	sky.sky_material = sky_material
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = AMBIENT_ENERGY
	env.ambient_light_sky_contribution = 0.0

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.45
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.02
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.05

	env.fog_enabled = true
	env.fog_light_color = FOG_COLOR
	env.fog_density = FOG_DENSITY
	env.fog_sky_affect = FOG_SKY_AFFECT
	env.fog_sun_scatter = 0.15
	env.fog_aerial_perspective = 0.35
	# Mobile costs: no screen-space effects, one shadow map.
	env.glow_enabled = false
	env.ssao_enabled = false
	env.ssil_enabled = false

	world_env.environment = env
	parent.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = SUN_ROTATION
	sun.light_color = SUN_COLOR
	sun.light_energy = SUN_ENERGY
	sun.light_angular_distance = SUN_ANGULAR_DIAMETER
	sun.shadow_enabled = true
	sun.shadow_blur = SUN_SHADOW_BLUR
	sun.shadow_opacity = SUN_SHADOW_OPACITY
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = SUN_SHADOW_MAX_DISTANCE
	sun.directional_shadow_fade_start = 0.85
	parent.add_child(sun)

	# A second light with shadows off is cheap: it is one more light in the
	# shader, not another shadow map.
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = FILL_ROTATION
	fill.light_color = FILL_COLOR
	fill.light_energy = FILL_ENERGY
	fill.shadow_enabled = false
	parent.add_child(fill)

	return {
		"world_environment": world_env,
		"environment": env,
		"sky_material": sky_material,
		"sun": sun,
		"fill": fill,
		# Filled in by main.gd once the forest exists: the one material shared
		# by every tree, whose wind strength the weather drives.
		"foliage_material": null,
	}

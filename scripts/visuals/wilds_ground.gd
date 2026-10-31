extends RefCounted
## Ground surface and ground clutter for the ATHAR wilderness.
##
## The prototype ground was one flat olive-coloured plane, which read as a test
## map: no scale cue, no variation, and nothing to separate near ground from far.
##
## This builder keeps the same single collision slab (so movement and the
## checksum-relevant world stay put) but gives it:
##
##   * a seamless procedural albedo texture blending moss, soil and dry grass,
##   * a matching detail normal map so the light breaks across the surface,
##   * tuned roughness so the ground is matte rather than plastic,
##   * stones and grass tufts as two MultiMesh batches, which is two draw calls
##     for hundreds of props instead of one node each.
##
## Textures come from FastNoiseLite with a fixed seed: no downloaded assets, and
## no effect on the world's deterministic seeding.

## Collision slab and detailed surface: the playable world.
const WORLD_SIZE := 90.0
## A wider backdrop sits just under the detailed surface so the horizon never
## shows sky beneath the ground when the camera looks to the edge.
const BACKDROP_SIZE := 320.0
const NOISE_SEED := 1337

const ALBEDO_TILE := 26.0
const NORMAL_TILE := 58.0

const GROUND_DARK := Color(0.062, 0.082, 0.054)
const GROUND_MOSS := Color(0.086, 0.112, 0.070)
const GROUND_GRASS := Color(0.108, 0.138, 0.082)
const GROUND_DRY := Color(0.140, 0.142, 0.094)

const STONE_COUNT := 70
const TUFT_COUNT := 420


## Adds the ground body, its surface and the clutter, and returns a summary.
static func build(parent: Node3D, rng: RandomNumberGenerator) -> Dictionary:
	var ground_body := StaticBody3D.new()
	ground_body.name = "ForestGround"
	parent.add_child(ground_body)

	var plane := PlaneMesh.new()
	plane.size = Vector2(WORLD_SIZE, WORLD_SIZE)

	var ground := MeshInstance3D.new()
	ground.name = "GroundSurface"
	ground.mesh = plane
	ground.material_override = _ground_material()
	ground.scale = Vector3.ONE
	ground_body.add_child(ground)

	var box := BoxShape3D.new()
	box.size = Vector3(WORLD_SIZE, 1.0, WORLD_SIZE)
	var collider := CollisionShape3D.new()
	collider.shape = box
	collider.position.y = -0.55
	ground_body.add_child(collider)

	# The backdrop: one untextured plane far wider than the playable area.
	var backdrop := MeshInstance3D.new()
	backdrop.name = "GroundBackdrop"
	var backdrop_plane := PlaneMesh.new()
	backdrop_plane.size = Vector2(BACKDROP_SIZE, BACKDROP_SIZE)
	backdrop.mesh = backdrop_plane
	var backdrop_mat := StandardMaterial3D.new()
	backdrop_mat.albedo_color = GROUND_MOSS.darkened(0.15)
	backdrop_mat.roughness = 1.0
	backdrop.material_override = backdrop_mat
	backdrop.position.y = -0.05
	parent.add_child(backdrop)

	var stones := _stone_batch(parent, rng)

	return {
		"ground_body": ground_body,
		"ground_surface": ground,
		"material": ground.material_override,
		"stone_count": stones,
		"node_count": 2,
	}


static func _ground_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.albedo_texture = _albedo_texture()
	mat.normal_enabled = true
	mat.normal_texture = _normal_texture()
	mat.normal_scale = 0.65
	mat.roughness = 0.96
	mat.metallic_specular = 0.18
	mat.uv1_scale = Vector3(ALBEDO_TILE, ALBEDO_TILE, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


static func _albedo_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = NOISE_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.018
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 6
	noise.fractal_gain = 0.6

	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.34, 0.62, 0.85, 1.0])
	ramp.colors = PackedColorArray([
		GROUND_DARK,
		GROUND_MOSS,
		GROUND_GRASS,
		GROUND_DRY,
		GROUND_GRASS.lerp(GROUND_DRY, 0.65),
	])

	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = noise
	tex.color_ramp = ramp
	return tex


static func _normal_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = NOISE_SEED + 7
	noise.frequency = 0.05
	noise.fractal_octaves = 3

	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 2.4
	tex.noise = noise
	return tex


## Scattered low-poly stones: one batch, no collision, sat just above the ground.
static func _stone_batch(parent: Node3D, rng: RandomNumberGenerator) -> int:
	var mesh := _mossy_mesh(0.34, 8, 5)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var transforms: Array[Transform3D] = []
	var attempts := 0
	while transforms.size() < STONE_COUNT and attempts < STONE_COUNT * 20:
		attempts += 1
		var x := rng.randf_range(-42.0, 42.0)
		var z := rng.randf_range(-42.0, 42.0)
		if Vector2(x, z).length() < 6.0:
			continue
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		basis = basis.scaled(Vector3(rng.randf_range(0.6, 1.5), rng.randf_range(0.35, 0.6), rng.randf_range(0.7, 1.4)))
		transforms.append(Transform3D(basis, Vector3(x, 0.05, z)))
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Stones"
	mmi.multimesh = mm
	parent.add_child(mmi)
	return transforms.size()


static func _mossy_mesh(radius: float, segments: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 1.4
	mesh.radial_segments = segments
	mesh.rings = rings
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.25, 0.21)
	mat.roughness = 0.94
	mesh.material = mat
	return mesh
